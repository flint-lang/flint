const std = @import("std");
const builtin = @import("builtin");

const Self = @This();

var state: ?Self = null;

toolchain_active: ?[]const u8,
toolchain_installed: []const []const u8,
fip_active: ?[]const u8,
fip_installed: struct {
    c: []const []const u8,
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
        , .{state.?.toolchain_active.?});
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

fn save(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !void {
    const state_path: []const u8 = switch (builtin.os.tag) {
        .windows => try std.fmt.allocPrint(allocator, "{s}\\state.zon", .{toolchain_path}),
        .linux => try std.fmt.allocPrint(allocator, "{s}/state.zon", .{toolchain_path}),
        else => @panic("Unsupported OS"),
    };
    defer allocator.free(state_path);

    const file: std.Io.File = try std.Io.Dir.cwd().openFile(io, state_path, .{});
    var file_writer = file.writer(io, &.{});
    try dump(&file_writer.interface);
    file.close(io);
}
