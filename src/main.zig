const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");

const defines = @import("defines");

const fip_cmd = @import("fip_cmd.zig");
const target_cmd = @import("target_cmd.zig");
const init_cmd = @import("init_cmd.zig");
const fetch_cmd = @import("fetch_cmd.zig");
const build_cmd = @import("build_cmd.zig");

const Registry = @import("Registry.zig");
const State = @import("State.zig");

const SubCommands = enum {
    help,
    // Other toolchain-related commands
    fip,
    target,
    // Core commands
    list,
    install,
    update,
    remove,
    @"switch",
    // Build-related commands
    init,
    fetch,
    build,
};
const parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
    .version = clap.parsers.string,
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit
    \\-v, --version Display the version information and exit
    \\<command>     The command to execute
);
const version_params = clap.parseParamsComptime(
    \\<version>     The Flint version to manage
);

fn getToolchainPath(io: std.Io, allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => blk: {
            const localappdata = environ_map.get("LOCALAPPDATA") orelse {
                std.log.err("Failed to get environment variable '%LOCALAPPDATA%'", .{});
                return error.GetToolchainPathFailed;
            };
            const full_path = try std.fmt.allocPrint(allocator, "{s}\\Flint\\Toolchain", .{localappdata});
            try std.Io.Dir.cwd().createDirPath(io, full_path);
            break :blk full_path;
        },
        .linux => blk: {
            const full_path =
                if (environ_map.get("XDG_DATA_HOME")) |xdg_data_home|
                    try std.fmt.allocPrint(allocator, "{s}/flint", .{xdg_data_home})
                else if (environ_map.get("HOME")) |home|
                    try std.fmt.allocPrint(allocator, "{s}/.local/share/flint", .{home})
                else {
                    std.log.err("Failed to get either environment variable '$XDG_DATA_HOME' or '$HOME'", .{});
                    return error.GetToolchainPathFailed;
                };
            try std.Io.Dir.cwd().createDirPath(io, full_path);
            break :blk full_path;
        },
        else => @panic("Unsupported OS"),
    };
}

pub fn main(init: std.process.Init) !u8 {
    // Allocator when I need more stack-frames visible, for example when fixing memory leaks
    // var gpa: std.heap.DebugAllocator(.{
    //     .stack_trace_frames = 20,
    // }) = .init;
    // defer std.debug.assert(gpa.deinit() == .ok);
    // const allocator = gpa.allocator();
    const allocator = init.gpa;

    var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &.{});
    const stderr = &stderr_writer.interface;

    const toolchain_path = try getToolchainPath(init.io, allocator, init.environ_map);
    defer allocator.free(toolchain_path);

    defer Registry.deinit(allocator);
    defer State.deinit(allocator);

    var iter = try init.minimal.args.iterateAllocator(allocator);
    defer iter.deinit();

    _ = iter.next();

    var diag_clap = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .diagnostic = &diag_clap,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch {
        std.log.err("Invalid <command>: {s}", .{init.minimal.args.vector[1]});
        try printHelp(stderr);
        return 1;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try printHelp(stdout);
        return 0;
    }
    if (res.args.version != 0) {
        try stdout.print("flint v{s} ({s}, {s})\n", .{ defines.version, defines.hash, defines.date });
        try stdout.flush();
        return 0;
    }

    const command = res.positionals[0] orelse {
        std.log.err("Missing required argument <command>", .{});
        try printHelp(stderr);
        return 1;
    };
    const version: []const u8 = switch (command) {
        .help, .fip, .target, .list => &.{},
        .install, .update, .remove, .@"switch" => blk: {
            var version_res = try clap.parseEx(clap.Help, &version_params, parsers, &iter, .{
                .diagnostic = &diag_clap,
                .allocator = allocator,
                .terminating_positional = 0,
            });
            defer version_res.deinit();
            const _version = version_res.positionals[0] orelse {
                std.log.err("Missing required argument <version> for '{s}'", .{@tagName(command)});
                try printHelp(stderr);
                return 1;
            };

            var iter_toolchain = (try Registry.get(init.io, allocator, toolchain_path)).toolchain.iterator();
            const version_found: bool = blk2: while (iter_toolchain.next()) |toolchain| {
                if (std.mem.eql(u8, toolchain.key_ptr.*, _version)) {
                    break :blk2 true;
                }
            } else false;
            if (!version_found) {
                std.log.err("Version '{s}' is not a known Flint versions.", .{_version});
                std.log.info("Execute 'flint list' to list all available versions.", .{});
                return 1;
            }

            break :blk _version;
        },
        .init, .fetch, .build => &.{},
    };
    switch (command) {
        .help => {
            try printHelp(stdout);
            return 0;
        },
        .fip => return fip_cmd.main(init.io, allocator, iter),
        .target => return target_cmd.main(init.io, allocator, iter),
        .list => {
            var iter_toolchain = (try Registry.get(init.io, allocator, toolchain_path)).toolchain.iterator();
            try stdout.writeAll("Available Flint versions:\n");
            var current = iter_toolchain.next();
            while (current) |toolchain| {
                const next = iter_toolchain.next();
                if (next != null) {
                    try stdout.print(" ├─ {s}", .{toolchain.key_ptr.*});
                } else {
                    try stdout.print(" └─ {s}", .{toolchain.key_ptr.*});
                }
                for ((try State.get(init.io, allocator, toolchain_path)).toolchain_installed) |installed| {
                    if (std.mem.eql(u8, installed, toolchain.key_ptr.*)) {
                        try stdout.writeAll(" [installed]");
                        break;
                    }
                }
                if ((try State.get(init.io, allocator, toolchain_path)).toolchain_active) |active| {
                    if (std.mem.eql(u8, active, toolchain.key_ptr.*)) {
                        try stdout.writeAll(" [active]");
                    }
                }
                try stdout.writeByte('\n');
                current = next;
            }
            try stdout.flush();
            return 0;
        },
        .install => {
            std.log.debug("'install' command not implemented yet: {s}", .{version});
            return 1;
        },
        .update => {
            std.log.debug("'update' command not implemented yet", .{});
            return 1;
        },
        .remove => {
            std.log.debug("'remove' command not implemented yet", .{});
            return 1;
        },
        .@"switch" => {
            std.log.debug("'switch' command not implemented yet", .{});
            return 1;
        },
        .init => return init_cmd.main(init.io, allocator, iter),
        .fetch => return fetch_cmd.main(init.io, allocator, iter),
        .build => return build_cmd.main(init.io, allocator, iter),
    }
    unreachable;
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: flint <command>
        \\
    );
    try clap.help(writer, clap.Help, &params, .{
        .indent = 2,
        .spacing_between_parameters = 0,
        .description_indent = 4,
        .description_on_new_line = false,
        .max_width = 100,
    });
    try writer.writeAll(
        \\
        \\  You can use '-h' or '--help' on any subcommand to get additional information
        \\
        \\Available commands are:
        \\  help                Print this help message
        \\  fip                 Manage installations of Flint Interop Modules like 'fip-c'
        \\  target              Manage target toolchains installations
        \\    install
        \\    remove
        \\    list
        \\
        \\  list                List all available and installed versions of Flint
        \\  install <version>   Install a specific version of Flint
        \\  update <version>    Check for updates of Flint
        \\  remove <version>    Remove a specific version of Flint
        \\  switch <version>    Use specific version of Flint
        \\
        \\  init                Initialize a new empty Flint project in the current working directory
        \\  fetch               Fetch all external dependencies described in the 'flint.toml' file
        \\  build               Build the Flint project from the information found in the '[build]' section of
        \\                      the 'flint.toml' file
        \\
    );
    try writer.flush();
}
