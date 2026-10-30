const std = @import("std");
const builtin = @import("builtin");

const Self = @This();

var state: ?Self = null;

toolchain_active: ?[]const u8,
toolchain_installed: [][]const u8,
fip_active: ?[]const u8,
fip_installed: struct {
    c: [][]const u8,
},

pub fn get(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !Self {
    if (state) |s| {
        return s;
    }

    const state_path: []const u8 = switch (builtin.os.tag) {
        .windows => try std.fmt.allocPrint(allocator, "{s}\\state.zon", .{toolchain_path}),
        .linux => try std.fmt.allocPrint(allocator, "{s}/state.zon", .{toolchain_path}),
        else => @panic("Unsupported OS"),
    };
    defer allocator.free(state_path);
    const state_file_content = std.Io.Dir.cwd().readFileAlloc(io, state_path, allocator, .unlimited) catch blk: {
        const file: std.Io.File = try std.Io.Dir.cwd().createFile(io, state_path, .{});
        var file_writer = file.writer(io, &.{});
        try file_writer.interface.writeAll(
            \\.{
            \\    .toolchain_active = null,
            \\    .toolchain_installed = .{},
            \\    .fip_active = null,
            \\    .fip_installed = .{
            \\        .c = .{},
            \\    },
            \\}
            \\
        );
        try file_writer.interface.flush();
        file.close(io);
        break :blk try std.Io.Dir.cwd().readFileAlloc(io, state_path, allocator, .unlimited);
    };
    defer allocator.free(state_file_content);
    const state_file_content_z = try allocator.dupeSentinel(u8, state_file_content, 0);
    defer allocator.free(state_file_content_z);

    state = try std.zon.parse.fromSliceAlloc(Self, allocator, state_file_content_z, null, .{});
    return state.?;
}

pub fn deinit(allocator: std.mem.Allocator) void {
    if (state == null) {
        return;
    }
    if (state.?.toolchain_active) |active| {
        allocator.free(active);
    }
    if (state.?.toolchain_installed.len > 0) {
        for (state.?.toolchain_installed) |installed| {
            allocator.free(installed);
        }
        allocator.free(state.?.toolchain_installed);
    }
    if (state.?.fip_active) |active| {
        allocator.free(active);
    }
    if (state.?.fip_installed.c.len > 0) {
        for (state.?.fip_installed.c) |installed| {
            allocator.free(installed);
        }
        allocator.free(state.?.fip_installed.c);
    }
}

pub fn dump(writer: *std.Io.Writer) !void {
    if (state == null) {
        try writer.writeAll(".{}\n");
        try writer.flush();
        return;
    }
    if (state.?.toolchain_active == null) {
        try writer.writeAll(
            \\.{
            \\    .toolchain_active = null,
            \\
        );
    } else {
        try writer.print(
            \\.{{
            \\    .toolchain_active = "{s}",
            \\
        , .{state.?.toolchain_active.?});
    }

    if (state.?.toolchain_installed.len == 0) {
        try writer.writeAll(
            \\    .toolchain_installed = .{},
            \\
        );
    } else {
        try writer.writeAll(
            \\    .toolchain_installed = .{
            \\
        );
        for (state.?.toolchain_installed) |installed| {
            try writer.print(
                \\        "{s}",
                \\
            , .{installed});
        }
        try writer.writeAll(
            \\     },
            \\
        );
    }

    if (state.?.fip_active == null) {
        try writer.writeAll(
            \\    .fip_active = null,
            \\
        );
    } else {
        try writer.print(
            \\    .fip_active = "{s}",
            \\
        , .{state.?.fip_active.?});
    }

    try writer.writeAll(
        \\    .fip_installed = .{
        \\        .c = .{
    );
    if (state.?.fip_installed.c.len == 0) {
        try writer.writeAll(
            \\},
            \\
        );
    } else {
        for (state.?.fip_installed.c) |installed| {
            try writer.print(
                \\            \"{s}\",
                \\
            , .{installed});
        }
        try writer.writeAll(
            \\        },
            \\
        );
    }

    try writer.writeAll(
        \\    },
        \\}
        \\
    );
}

pub fn addToolchainInstalled(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8, new: []const u8) !void {
    std.debug.assert(state != null);
    if (state.?.toolchain_active == null) {
        // Use newly installed version if it is the first version to install
        state.?.toolchain_active = try allocator.dupe(u8, new);
    }

    for (state.?.toolchain_installed) |installed| {
        if (std.mem.eql(u8, new, installed)) {
            // Already present, we dont need to add it to the list
            break;
        }
    } else {
        // Newly added, so we need to add it to the list
        state.?.toolchain_installed = try allocator.realloc(state.?.toolchain_installed, state.?.toolchain_installed.len + 1);
        state.?.toolchain_installed[state.?.toolchain_installed.len - 1] = try allocator.dupe(u8, new);
    }

    try save(io, allocator, toolchain_path);
}

pub fn removeToolchainInstalled(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8, version: []const u8) !void {
    _ = try get(io, allocator, toolchain_path);

    if (state.?.toolchain_active) |active| {
        if (std.mem.eql(u8, version, active)) {
            // We are removing the currently active version, meaning that no version is active any more
            allocator.free(active);
            state.?.toolchain_active = null;
        }
    }

    var new_list: std.ArrayList([]const u8) = .empty;
    defer new_list.deinit(allocator);
    var removed: bool = false;
    for (state.?.toolchain_installed) |installed| {
        if (std.mem.eql(u8, version, installed)) {
            std.debug.assert(!removed);
            allocator.free(installed);

            const version_path = try std.fmt.allocPrint(allocator, "{0s}{1c}toolchain{1c}{2s}", .{ toolchain_path, std.Io.Dir.path.sep, version });
            defer allocator.free(version_path);
            try std.Io.Dir.cwd().deleteTree(io, version_path);
            removed = true;
            continue;
        }
        try new_list.append(allocator, installed);
    } else if (!removed) {
        std.log.err("Version '{0s}' is not installed and thus cannot be removed", .{version});
        return error.VersionNotPresent;
    }
    allocator.free(state.?.toolchain_installed);
    state.?.toolchain_installed = try new_list.toOwnedSlice(allocator);

    try save(io, allocator, toolchain_path);
}

pub fn setActiveToolchain(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8, version: []const u8) !void {
    _ = try get(io, allocator, toolchain_path);

    for (state.?.toolchain_installed) |installed| {
        if (std.mem.eql(u8, version, installed)) {
            // Everything okay, the version we want to switch to is installed
            break;
        }
    } else {
        std.log.err("Version '{0s}' is not yet installed. Run 'flint install {0s}' first.", .{version});
        return error.VersionNotPresent;
    }

    if (state.?.toolchain_active) |old_active| {
        if (std.mem.eql(u8, old_active, version)) {
            return;
        }
        allocator.free(old_active);
    }
    state.?.toolchain_active = try allocator.dupe(u8, version);

    try save(io, allocator, toolchain_path);
}

fn save(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !void {
    const state_path: []const u8 = switch (builtin.os.tag) {
        .windows => try std.fmt.allocPrint(allocator, "{s}\\state.zon", .{toolchain_path}),
        .linux => try std.fmt.allocPrint(allocator, "{s}/state.zon", .{toolchain_path}),
        else => @panic("Unsupported OS"),
    };
    defer allocator.free(state_path);

    const file: std.Io.File = try std.Io.Dir.cwd().createFile(io, state_path, .{});
    defer file.close(io);
    var file_writer = file.writerStreaming(io, &.{});
    try dump(&file_writer.interface);
    try file_writer.flush();

    // Always delete the active symlink, only re-create it if a toolchain is active
    const sep = std.Io.Dir.path.sep;
    const active_path = try std.fmt.allocPrint(allocator, "{0s}{1c}toolchain{1c}active", .{ toolchain_path, sep });
    defer allocator.free(active_path);
    std.Io.Dir.cwd().deleteFile(io, active_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    if (state.?.toolchain_active) |target| {
        const target_path = try std.fmt.allocPrint(allocator, "{0s}{1c}toolchain{1c}{2s}", .{ toolchain_path, sep, target });
        defer allocator.free(target_path);

        try std.Io.Dir.cwd().symLink(io, target_path, active_path, .{ .is_directory = true });
    }
}
