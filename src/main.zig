const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");

const defines = @import("defines");

const init_cmd = @import("init_cmd.zig");
const fetch_cmd = @import("fetch_cmd.zig");
const build_cmd = @import("build_cmd.zig");
const core_cmd = @import("core_cmd.zig");
const fip_cmd = @import("fip_cmd.zig");
const target_cmd = @import("target_cmd.zig");

const Registry = @import("Registry.zig");

const SubCommands = enum {
    help,
    init,
    fetch,
    build,
    core,
    fip,
    target,
};
const parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit
    \\-v, --version Display the version information and exit
    \\<command>     The command to execute
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
            const xdg_data_home = environ_map.get("XDG_DATA_HOME") orelse {
                std.log.err("Failed to get environment variable '$XDG_DATA_HOME'", .{});
                return error.GetToolchainPathFailed;
            };
            const full_path = try std.fmt.allocPrint(allocator, "{s}/flint", .{xdg_data_home});
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

    const registry: Registry = try .get(init.io, allocator, toolchain_path);
    _ = registry;
    try Registry.dump(stdout);
    defer Registry.deinit(allocator);

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
    return switch (command) {
        .help => blk: {
            try printHelp(stdout);
            break :blk 0;
        },
        .init => init_cmd.main(init.io, allocator, iter),
        .build => build_cmd.main(init.io, allocator, iter),
        .fetch => fetch_cmd.main(init.io, allocator, iter),
        .core => core_cmd.main(init.io, allocator, iter),
        .fip => fip_cmd.main(init.io, allocator, iter),
        .target => target_cmd.main(init.io, allocator, iter),
    };
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
        \\  help            Print this help message
        \\  init            Initialize a new empty Flint project in the current working directory
        \\  fetch           Fetch all external dependencies described in the 'flint.toml' file
        \\  build           Build the Flint project from the information found in the '[build]' section of the
        \\                  'flint.toml' file
        \\  core            Manage installations of Core parts of Flint, like the compiler or lsp
        \\  fip             Manage installations of Flint Interop Modules like 'fip-c'
        \\  target          Manage target toolchains installations
        \\    install
        \\    remove
        \\    list
        \\
    );
    try writer.flush();
}
