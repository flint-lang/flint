const std = @import("std");
const builtin = @import("builtin");

const net = @import("net.zig");

const Self = @This();

var registry: ?Self = null;
var newest_toolchain_release: ?[]const u8 = null;

toolchain: []Toolchain,
fip: []Fip,

pub const Toolchain = struct {
    version: []const u8,
    fip_version: []const u8,
    bundles: []const Bundle,
    platforms: []Platform,

    pub const Bundle = struct {
        id: []const u8,
        shasum: []const u8,
    };

    pub const Platform = struct {
        platform: []const u8,
        flintc: Artifact,
        fls: Artifact,

        pub const Artifact = struct {
            url: []const u8,
            shasum: []const u8,
        };
    };
};

pub const Fip = struct {
    version: []const u8,
    modules: []Module,

    pub const Module = struct {
        language: []const u8,
        platforms: []Platform,

        pub const Platform = struct {
            platform: []const u8,
            url: []const u8,
            shasum: []const u8,
        };
    };
};

pub fn getNewestToolchainVersion(io: std.Io, allocator: std.mem.Allocator, arena: std.mem.Allocator, toolchain_path: []const u8) ![]const u8 {
    _ = try get(io, allocator, arena, toolchain_path);
    return newest_toolchain_release.?;
}

pub fn get(io: std.Io, allocator: std.mem.Allocator, arena: std.mem.Allocator, toolchain_path: []const u8) !Self {
    if (registry) |reg| {
        return reg;
    }

    const registry_content = try getRegistryFileContent(io, allocator, toolchain_path);
    defer allocator.free(registry_content);

    var diag_zon: std.zon.parse.Diagnostics = undefined;
    errdefer diag_zon.log("registry.zon");

    registry = try std.zon.parse.fromSlice(Self, .{
        .gpa = allocator,
        .arena = arena,
        .source = registry_content,
        .diagnostics = &diag_zon,
    });
    newest_toolchain_release = registry.?.toolchain[0].version;

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    try diag_zon.fmt("registry.zon").format(stdout);

    return registry.?;
}

pub fn deinit() void {
    registry = null;
    newest_toolchain_release = null;
}

pub fn delete(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !void {
    deinit();

    const registry_path = try std.fmt.allocPrint(allocator, "{s}{c}registry.zon", .{ toolchain_path, std.Io.Dir.path.sep });
    defer allocator.free(registry_path);

    std.Io.Dir.cwd().deleteFile(io, registry_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

pub fn dump(writer: *std.Io.Writer) !void {
    if (registry == null) {
        try writer.writeAll(".{}\n");
        try writer.flush();
        return;
    }
    try writer.writeAll(
        \\.{
        \\    .toolchain = .{
        \\
    );
    for (registry.?.toolchain) |toolchain| {
        try writer.print(
            \\        .{{
            \\            .version = "{s}",
            \\            .fip_version = "{s}",
            \\            .bundles = .{
        , .{
            toolchain.version,
            toolchain.fip_version,
        });
        if (toolchain.bundles.len == 0) {
            try writer.writeAll(
                \\},
                \\
            );
        } else {
            for (toolchain.bundles) |bundle| {
                try writer.print(
                    \\                .{ .id = "{s}", .shasum = "{s}" },
                    \\
                , .{ bundle.id, bundle.shasum });
            }
        }
        try writer.writeAll(
            \\            .platforms = .{{
            \\
        );
        for (toolchain.platforms) |platform| {
            try writer.print(
                \\                .{{
                \\                    .platform = "{s}",
                \\                    .flintc = .{{
                \\                        .url = "{s}",
                \\                        .shasum = "{s}",
                \\                    }},
                \\                    .fls = .{{
                \\                        .url = "{s}",
                \\                        .shasum = "{s}",
                \\                    }},
                \\                }},
                \\
            , .{
                platform.platform,
                platform.flintc.url,
                platform.flintc.shasum,
                platform.fls.url,
                platform.fls.shasum,
            });
        }
        try writer.writeAll(
            \\            },
            \\        },
            \\
        );
    }
    try writer.writeAll(
        \\    },
        \\    .fip = .{
        \\
    );
    for (registry.?.fip) |fip| {
        try writer.print(
            \\        .{{
            \\            .version = "{s}",
            \\            .modules = .{{
            \\
        , .{
            fip.version,
        });
        for (fip.modules) |module| {
            try writer.print(
                \\                .{{
                \\                    .language = "{s}",
                \\                    .platforms = .{{
            , .{
                module.language,
            });
            try writer.writeAll(
                \\                }},
                \\
            );
            for (module.platforms) |platform| {
                try writer.print(
                    \\                    .{{
                    \\                        .platform = "{s}",
                    \\                        .url = "{s}",
                    \\                        .shasum = "{s}",
                    \\                    },
                    \\
                , .{
                    platform.platform,
                    platform.url,
                    platform.shasum,
                });
            }
            try writer.writeAll(
                \\                },
                \\
            );
        }
        try writer.writeAll(
            \\            },
            \\        },
            \\
        );
    }
    try writer.writeAll(
        \\    },
        \\}
        \\
    );
    try writer.flush();
}

pub fn getToolchainFromVersion(version: []const u8) !*Toolchain {
    for (registry.?.toolchain) |*toolchain| {
        if (std.mem.eql(u8, toolchain.version, version)) {
            return toolchain;
        }
    }
    return error.ToolchainVersionNotFound;
}

fn getRegistryFileContent(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) ![:0]const u8 {
    const url = "https://raw.githubusercontent.com/flint-lang/flint/main/registry.zon";
    const registry_path: []const u8 = switch (builtin.os.tag) {
        .windows => try std.fmt.allocPrint(allocator, "{s}\\registry.zon", .{toolchain_path}),
        .linux => try std.fmt.allocPrint(allocator, "{s}/registry.zon", .{toolchain_path}),
        else => @panic("Unsupported OS"),
    };
    defer allocator.free(registry_path);
    if (std.Io.Dir.cwd().readFileAlloc(io, registry_path, allocator, .unlimited)) |content| {
        defer allocator.free(content);
        return allocator.dupeSentinel(u8, content, 0);
    } else |_| {
        // Fetch registry, it does not exist yet
        try net.downloadFile(io, allocator, url, registry_path);
        const content = try std.Io.Dir.cwd().readFileAlloc(io, registry_path, allocator, .unlimited);
        defer allocator.free(content);
        return allocator.dupeSentinel(u8, content, 0);
    }
}
