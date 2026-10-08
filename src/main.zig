const std = @import("std");
const clap = @import("clap");

const defines = @import("defines");

const init_cmd = @import("init_cmd.zig");
const fetch_cmd = @import("init_cmd.zig");
const build_cmd = @import("init_cmd.zig");
const core_cmd = @import("init_cmd.zig");
const fip_cmd = @import("init_cmd.zig");
const target_cmd = @import("init_cmd.zig");

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
    \\-h, --help    Display this help and exit.
    \\<command>     The command to execute
);

pub fn main(init: std.process.Init) !void {
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
        return;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try printHelp(stdout);
        return;
    }

    const command = res.positionals[0] orelse {
        std.log.err("Missing required argument <command>", .{});
        try printHelp(stderr);
        return;
    };
    return switch (command) {
        .help => printHelp(stdout),
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
        \\  fetch           Fetch all external dependencies described in the 'flint.toml' file
        \\  build           Build the Flint project from the information found in the '[build]' section of the
        \\                  'flint.toml' file
        \\  core            Manage Core functionality of Flint, like the compiler or lsp
        \\    install       Install a specific version of Flint     ('flintc', 'fls', etc)
        \\    update        Check for updates of Flint              ('flintc', 'fls', etc)
        \\    remove        Remove a specific version of Flint      ('flintc', 'fls', etc)
        \\    list          List all installed versions of Flint    ('flintc', 'fls', etc)
        \\    use           Use specific version of Flint           ('flintc', 'fls', etc)
        \\  fip             Manage Flint Interop Modules like 'fip-c'
        \\    install
        \\    update
        \\    remove
        \\    list
        \\  target          Manage target toolchains files
        \\    install
        \\    remove
        \\    list
        \\
    );
}
