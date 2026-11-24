const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");

const net = @import("net.zig");
const extract = @import("extract.zig");

const Toml = @import("Toml.zig");

pub fn main(io: std.Io, environ_map: *std.process.Environ.Map, gpa: std.mem.Allocator, arena: std.mem.Allocator) !u8 {
    const toml: Toml = try Toml.get(io, arena);

    const flint_dir: std.Io.Dir = if (std.Io.Dir.cwd().openDir(io, "flint", .{})) |dir| dir else |_| blk: {
        try std.Io.Dir.cwd().createDir(io, "flint", .default_dir);
        break :blk try std.Io.Dir.cwd().openDir(io, "flint", .{});
    };
    defer flint_dir.close(io);

    try flint_dir.writeFile(io, .{
        .sub_path = ".gitignore",
        .data =
        \\.gitignore
        \\.pkg
        \\.gen
        \\
        ,
    });

    const flint_pkg_cache_path: []const u8 = try getPkgCacheDir(environ_map, gpa);
    defer gpa.free(flint_pkg_cache_path);
    try std.Io.Dir.cwd().createDirPath(io, flint_pkg_cache_path);

    const flint_pkg_dir = if (flint_dir.openDir(io, ".pkg", .{})) |dir| dir else |_| blk: {
        try flint_dir.createDir(io, ".pkg", .default_dir);
        break :blk try flint_dir.openDir(io, ".pkg", .{});
    };
    defer flint_pkg_dir.close(io);

    var flint_pkg_path_buffer: [std.Io.Dir.max_path_bytes]u8 = @splat(0);
    const flint_pkg_path_len = try flint_pkg_dir.realPath(io, &flint_pkg_path_buffer);
    const flint_pkg_path: []const u8 = flint_pkg_path_buffer[0..flint_pkg_path_len];

    for (toml.deps) |dep| {
        switch (dep.src) {
            .none => unreachable,
            .path => return error.NotImplementedYet,
            .link => |link| {
                const dep_dir_path: []const u8 = try gpa.print("{s}{c}{s}", .{ flint_pkg_path, std.fs.path.sep, link.sha256 });
                defer gpa.free(dep_dir_path);

                const full_url: []const u8 = switch (link.tag_or_rev) {
                    .none => unreachable,
                    .tag => |tag| try gpa.print("{s}/archive/refs/tags/{s}.tar.gz", .{ link.url, tag }),
                    .rev => |rev| try gpa.print("{s}/archive/{s}.tar.gz", .{ link.url, rev }),
                };
                defer gpa.free(full_url);

                const tmp_file_path: []const u8 = try gpa.print("{s}{c}{s}.tar.gz", .{ flint_pkg_cache_path, std.fs.path.sep, link.sha256 });
                defer gpa.free(tmp_file_path);

                if (std.Io.Dir.cwd().openFile(io, tmp_file_path, .{})) |open| open.close(io) else |_| {
                    std.log.info("Fetching dependency '{s}'...", .{dep.name});
                    try net.downloadFile(io, gpa, full_url, tmp_file_path);
                    try net.checkFileIntegrity(io, gpa, tmp_file_path, link.sha256);
                }

                if (std.Io.Dir.cwd().openDir(io, dep_dir_path, .{})) |open| open.close(io) else |_| {
                    try std.Io.Dir.cwd().deleteTree(io, dep_dir_path);
                    try std.Io.Dir.cwd().createDir(io, dep_dir_path, .default_dir);
                    try extract.tarGz(io, gpa, tmp_file_path, dep_dir_path, 1);
                }
            },
        }
    }
    return 0;
}

fn getPkgCacheDir(environ_map: *std.process.Environ.Map, allocator: std.mem.Allocator) ![]const u8 {
    const sep = std.fs.path.sep;
    switch (builtin.os.tag) {
        .linux => {
            if (environ_map.get("XDG_CACHE_HOME")) |xdg_cache| {
                return allocator.print("{0s}{1c}flint{1c}pkg", .{ xdg_cache, sep });
            } else if (environ_map.get("HOME")) |home| {
                return allocator.print("{0s}{1c}.cache{1c}flint{1c}pkg", .{ home, sep });
            } else {
                return error.EnvironMapBrokenOnLinux;
            }
            unreachable;
        },
        .windows => {
            const localappdata = environ_map.get("LOCALAPPDATA") orelse
                return error.LocalAppDataNotSet;
            return allocator.print("{0s}{1c}Flint{1c}cache{1c}pkg", .{ localappdata, sep });
        },
        else => @panic("Unsupported OS"),
    }
    unreachable;
}
