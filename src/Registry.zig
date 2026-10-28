const std = @import("std");
const builtin = @import("builtin");

const Self = @This();

var registry: ?Self = null;

toolchain: std.StringArrayHashMapUnmanaged(ToolchainRelease),
fip: std.StringArrayHashMapUnmanaged(FipRelease),

const Artifact = struct {
    url: []const u8,
    shasum: []const u8,

    pub fn deinit(self: *Artifact, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.shasum);
    }
};

const ToolchainRelease = struct {
    fip_version: []const u8,
    artifacts: std.StringArrayHashMapUnmanaged(PlatformArtifacts),

    const PlatformArtifacts = struct {
        flintc: Artifact,
        fls: Artifact,
    };

    pub fn parse(
        allocator: std.mem.Allocator,
        zoir: std.zig.Zoir,
        ast: std.zig.Ast,
        names: []const std.zig.Zoir.NullTerminatedString,
        vals: std.zig.Zoir.Node.Index.Range,
    ) !ToolchainRelease {
        var release: ToolchainRelease = .{
            .fip_version = undefined,
            .artifacts = .empty,
        };

        const fip_version_name = names[0].get(zoir);
        if (!std.mem.eql(u8, fip_version_name, "fip_version")) {
            std.log.err("Expected field 'fip_version' in toolchain release but got {s}", .{fip_version_name});
            return error.UnexpectedFieldInRelease;
        }
        release.fip_version = switch (vals.at(0).get(zoir)) {
            .string_literal => |fip_version| try allocator.dupe(u8, fip_version),
            else => return error.ExpectedStringLiteral,
        };

        const artifacts_name = names[1].get(zoir);
        if (!std.mem.eql(u8, artifacts_name, "artifacts")) {
            std.log.err("Expected field 'artifacts' in toolchain release but got {s}", .{artifacts_name});
            return error.UnexpectedFieldInRelease;
        }
        const artifacts_struct = switch (vals.at(1).get(zoir)) {
            .struct_literal => |artifact| artifact,
            else => return error.ExpectedStructLiteral,
        };

        for (artifacts_struct.names, 0..artifacts_struct.vals.len) |platform_node, k| {
            try release.artifacts.put(
                allocator,
                try allocator.dupe(u8, platform_node.get(zoir)),
                try std.zon.parse.fromZoirNodeAlloc(
                    PlatformArtifacts,
                    allocator,
                    ast,
                    zoir,
                    artifacts_struct.vals.at(@intCast(k)),
                    null,
                    .{},
                ),
            );
        }
        return release;
    }

    pub fn deinit(self: *ToolchainRelease, allocator: std.mem.Allocator) void {
        allocator.free(self.fip_version);
        var iter = self.artifacts.iterator();
        while (iter.next()) |*artifacts| {
            allocator.free(artifacts.key_ptr.*);
            artifacts.value_ptr.flintc.deinit(allocator);
            artifacts.value_ptr.fls.deinit(allocator);
        }
        self.artifacts.deinit(allocator);
    }
};

const FipRelease = struct {
    c: std.StringArrayHashMapUnmanaged(Artifact),

    pub fn parse(
        allocator: std.mem.Allocator,
        zoir: std.zig.Zoir,
        ast: std.zig.Ast,
        names: []const std.zig.Zoir.NullTerminatedString,
        vals: std.zig.Zoir.Node.Index.Range,
    ) !FipRelease {
        var release: FipRelease = .{
            .c = .empty,
        };

        for (names, 0..vals.len) |language_node, i| {
            const language = language_node.get(zoir);
            const language_struct = switch (vals.at(@intCast(i)).get(zoir)) {
                .struct_literal => |s| s,
                else => return error.ExpectedStruct,
            };

            if (std.mem.eql(u8, language, "c")) {
                for (language_struct.names, 0..language_struct.vals.len) |platform_node, j| {
                    try release.c.put(
                        allocator,
                        try allocator.dupe(u8, platform_node.get(zoir)),
                        try std.zon.parse.fromZoirNodeAlloc(
                            Artifact,
                            allocator,
                            ast,
                            zoir,
                            language_struct.vals.at(@intCast(j)),
                            null,
                            .{},
                        ),
                    );
                }
            } else {}
        }
        return release;
    }

    pub fn deinit(self: *FipRelease, allocator: std.mem.Allocator) void {
        var iter = self.c.iterator();
        while (iter.next()) |*artifact| {
            allocator.free(artifact.key_ptr.*);
            artifact.value_ptr.deinit(allocator);
        }
        self.c.deinit(allocator);
    }
};

pub fn get(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !Self {
    if (registry) |reg| {
        return reg;
    }

    const registry_content = try getRegistryFileContent(io, allocator, toolchain_path);
    defer allocator.free(registry_content);

    var diag_zon: std.zon.parse.Diagnostics = .{};
    defer diag_zon.deinit(allocator);

    var ast = try std.zig.Ast.parse(allocator, registry_content, .zon);
    defer ast.deinit(allocator);

    var zoir = try std.zig.ZonGen.generate(allocator, ast, .{ .parse_str_lits = true });
    defer zoir.deinit(allocator);

    const root = std.zig.Zoir.Node.Index.root.get(zoir);
    const root_struct = switch (root) {
        .struct_literal => |s| s,
        else => return error.ExpectedStruct,
    };

    var result: Self = .{
        .toolchain = .empty,
        .fip = .empty,
    };

    for (root_struct.names, 0..root_struct.vals.len) |name_node, f| {
        const name = name_node.get(zoir);
        const value_node = root_struct.vals.at(@intCast(f));

        if (std.mem.eql(u8, name, "toolchain")) {
            const toolchain_struct = switch (value_node.get(zoir)) {
                .struct_literal => |s| s,
                else => return error.ExpectedStruct,
            };
            for (toolchain_struct.names, 0..toolchain_struct.vals.len) |version, j| {
                const release_struct = switch (toolchain_struct.vals.at(@intCast(j)).get(zoir)) {
                    .struct_literal => |s| s,
                    else => return error.ExpectedStruct,
                };
                try result.toolchain.put(allocator, try allocator.dupe(u8, version.get(zoir)), try ToolchainRelease.parse(
                    allocator,
                    zoir,
                    ast,
                    release_struct.names,
                    release_struct.vals,
                ));
            }
        } else if (std.mem.eql(u8, name, "fip")) {
            const fip_struct = switch (value_node.get(zoir)) {
                .struct_literal => |s| s,
                else => return error.ExpectedStruct,
            };
            for (fip_struct.names, 0..fip_struct.vals.len) |version, j| {
                const release_struct = switch (fip_struct.vals.at(@intCast(j)).get(zoir)) {
                    .struct_literal => |s| s,
                    else => return error.ExpectedStruct,
                };
                try result.fip.put(allocator, try allocator.dupe(u8, version.get(zoir)), try FipRelease.parse(
                    allocator,
                    zoir,
                    ast,
                    release_struct.names,
                    release_struct.vals,
                ));
            }
        } else {
            std.log.err("Unknown field at top level in registry: {s}", .{name});
            return error.MalformedRegistry;
        }
    }

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    try diag_zon.format(stdout);

    registry = result;
    return result;
}

pub fn deinit(allocator: std.mem.Allocator) void {
    if (registry == null) {
        return;
    }
    // free nested maps + strings as needed
    var iter1 = registry.?.toolchain.iterator();
    while (iter1.next()) |release| {
        allocator.free(release.key_ptr.*);
        release.value_ptr.deinit(allocator);
    }
    registry.?.toolchain.deinit(allocator);

    var iter2 = registry.?.fip.iterator();
    while (iter2.next()) |release| {
        allocator.free(release.key_ptr.*);
        release.value_ptr.deinit(allocator);
    }
    registry.?.fip.deinit(allocator);
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
    var iter_toolchain = registry.?.toolchain.iterator();
    while (iter_toolchain.next()) |release| {
        const toolchain_release = release.value_ptr.*;
        try writer.print(
            \\        .@"{s}" = .{{
            \\            .fip_version = "{s}",
            \\            .artifacts = .{{
            \\
        , .{
            release.key_ptr.*,
            toolchain_release.fip_version,
        });
        var iter_artifacts = toolchain_release.artifacts.iterator();
        while (iter_artifacts.next()) |artifact| {
            const flintc = artifact.value_ptr.flintc;
            const fls = artifact.value_ptr.fls;
            try writer.print(
                \\                .@"{s}" = .{{
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
                artifact.key_ptr.*,
                flintc.url,
                flintc.shasum,
                fls.url,
                fls.shasum,
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
    var iter_fip = registry.?.fip.iterator();
    while (iter_fip.next()) |release| {
        try writer.print(
            \\        .@"{s}" = .{{
            \\            .c = .{{
            \\
        , .{
            release.key_ptr.*,
        });
        var iter_c = release.value_ptr.c.iterator();
        while (iter_c.next()) |artifact| {
            try writer.print(
                \\                .@"{s}" = .{{
                \\                    .url = "{s}",
                \\                    .shasum = "{s}",
                \\                }},
                \\
            , .{
                artifact.key_ptr.*,
                artifact.value_ptr.url,
                artifact.value_ptr.shasum,
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
        \\}
        \\
    );
    try writer.flush();
}

fn downloadFile(io: std.Io, allocator: std.mem.Allocator, url: []const u8, file_path: []const u8) !void {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var file = try std.Io.Dir.cwd().createFile(io, file_path, .{ .truncate = true });
    defer file.close(io);

    var file_buf: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &file_buf);

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &file_writer.interface,
    });
    try file_writer.interface.flush();

    if (result.status.class() != .success) {
        std.log.err("download failed: {d} {s}", .{
            @intFromEnum(result.status),
            result.status.phrase() orelse "unknown",
        });
        return error.HttpRequestFailed;
    }
}

fn getRegistryFileContent(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) ![:0]const u8 {
    const url = "https://raw.githubusercontent.com/flint-lang/flint/main/registry.zon";
    const registry_path: []const u8 = try std.fmt.allocPrint(allocator, "{s}/registry.zon", .{toolchain_path});
    defer allocator.free(registry_path);
    if (std.Io.Dir.cwd().readFileAlloc(io, registry_path, allocator, .unlimited)) |content| {
        defer allocator.free(content);
        return allocator.dupeSentinel(u8, content, 0);
    } else |_| {
        // Fetch registry, it does not exist yet
        try downloadFile(io, allocator, url, registry_path);
        const content = try std.Io.Dir.cwd().readFileAlloc(io, registry_path, allocator, .unlimited);
        defer allocator.free(content);
        return allocator.dupeSentinel(u8, content, 0);
    }
}
