const std = @import("std");
const clap = @import("clap");

const SubCommands = enum {
    help,
    list,
    install,
    update,
    remove,
    @"switch",
};
const parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit
    \\<command>     The command to execute
);

pub fn main(io: std.Io, gpa: std.mem.Allocator, iter_start: std.process.Args.Iterator) !u8 {
    var iter: std.process.Args.Iterator = iter_start;

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    var diag = clap.Diagnostic{};
    var res = try clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    });
    defer res.deinit();
    if (res.args.help != 0) {
        try printHelp(stdout);
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
        .list => {
            std.log.debug("'list' command not implemented yet", .{});
            return 1;
        },
        .install => {
            std.log.debug("'install' command not implemented yet", .{});
            return 1;
        },
        .update => {
            std.log.debug("'list' command not implemented yet", .{});
            return 1;
        },
        .remove => {
            std.log.debug("'list' command not implemented yet", .{});
            return 1;
        },
        .@"switch" => {
            std.log.debug("'list' command not implemented yet", .{});
            return 1;
        },
    };
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: flint core <command>
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
        \\When installing, updating or changing version of Flint, these are changed:
        \\  flintc          The compiler itself
        \\  fls             The language server
        \\  Core            Documentation stubs for all Core modules of this version
        \\
        \\Available commands are:
        \\  help                Print this help message
        \\  list                List all available and installed versions of Flint
        \\  install <version>   Install a specific version of Flint
        \\  update <version>    Check for updates of Flint
        \\  remove <version>    Remove a specific version of Flint
        \\  switch <version>    Use specific version of Flint
        \\
    );
    try writer.flush();
}
