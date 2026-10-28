const std = @import("std");
const clap = @import("clap");

const Commands = enum {
    help,
    list,
    install,
    update,
    remove,
    @"switch",
};
const Languages = enum {
    c,
};
const parsers = .{
    .command = clap.parsers.enumeration(Commands),
    .language = clap.parsers.enumeration(Languages),
    .version = clap.parsers.string,
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit
    \\<command>     The command to execute
);
const language_params = clap.parseParamsComptime(
    \\<language>
);
const version_params = clap.parseParamsComptime(
    \\<version>
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
        .terminating_positional = 0,
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
    const language: Languages = switch (command) {
        .help => .c,
        else => blk: {
            var language_res = try clap.parseEx(clap.Help, &language_params, parsers, &iter, .{
                .diagnostic = &diag,
                .allocator = gpa,
                .terminating_positional = 0,
            });
            defer language_res.deinit();
            break :blk language_res.positionals[0] orelse {
                std.log.err("Missing required argument <language> for subcommand '{s}'", .{@tagName(command)});
                try printHelp(stderr);
                return 1;
            };
        },
    };
    _ = language;
    const version: []const u8 = switch (command) {
        .help, .list => &.{},
        else => blk: {
            var version_res = try clap.parseEx(clap.Help, &version_params, parsers, &iter, .{
                .diagnostic = &diag,
                .allocator = gpa,
                .terminating_positional = 0,
            });
            defer version_res.deinit();
            break :blk version_res.positionals[0] orelse {
                std.log.err("Missing required argument <version> for subcommand '{s}'", .{@tagName(command)});
                try printHelp(stderr);
                return 1;
            };
        },
    };
    _ = version;
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
    };
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: flint fip <command>
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
        \\  help                            Print this help message
        \\  list <language>                 List all available and installed versions of the 'fip-<language>'
        \\                                  Interop Module
        \\  install <language> <version>    Install a specific <version> of the 'fip-<language>' IM
        \\  update <language> <version>     Check for updates of the 'fip-<language>' IM
        \\  remove <language> <version>     Remove a specific version of the 'fip-<language>' IM
        \\  switch <language> <version>     Use specific version of the 'fip-<language>' IM
        \\
        \\Available languages are:
        \\  c   The C programming language Interop Module
        \\
    );
    try writer.flush();
}
