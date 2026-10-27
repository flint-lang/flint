const std = @import("std");
const clap = @import("clap");

const defines = @import("defines");

const init_cmd = @import("init_cmd.zig");
const fetch_cmd = @import("fetch_cmd.zig");
const build_cmd = @import("build_cmd.zig");
const core_cmd = @import("core_cmd.zig");
const fip_cmd = @import("fip_cmd.zig");
const target_cmd = @import("target_cmd.zig");

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

pub fn main(init: std.process.Init) !u8 {
    var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &.{});
    const stderr = &stderr_writer.interface;

    var iter = try init.minimal.args.iterateAllocator(init.gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
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
        .init => init_cmd.main(init.io, init.gpa, iter),
        .build => build_cmd.main(init.io, init.gpa, iter),
        .fetch => fetch_cmd.main(init.io, init.gpa, iter),
        .core => core_cmd.main(init.io, init.gpa, iter),
        .fip => fip_cmd.main(init.io, init.gpa, iter),
        .target => target_cmd.main(init.io, init.gpa, iter),
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
        \\Available commands are:
        \\  help            Print this help message
        \\  init            Initialize a new empty Flint project in the current working directory
        \\                  (use '-h' or '--help' for more information)
        \\  fetch           Fetch all external dependencies described in the 'flint.toml' file
        \\  build           Build the Flint project from the information found in the '[build]' section of the
        \\                  'flint.toml' file
        \\  core            Manage installations of Core parts of Flint, like the compiler or lsp
        \\                  (use '-h', '--help' or 'help' for more information)
        \\  fip             Manage Flint Interop Modules like 'fip-c'
        \\                  (use '-h', '--help' or 'help' for more information)
        \\    install
        \\    update
        \\    remove
        \\    list
        \\  target          Manage target toolchains files
        \\                  (use '-h', '--help' or 'help' for more information)
        \\    install
        \\    remove
        \\    list
        \\
    );
    try writer.flush();
}
