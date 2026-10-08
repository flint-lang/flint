const std = @import("std");
const clap = @import("clap");

const parsers = .{
    .dir = clap.parsers.string,
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit.
    \\<dir>         Initialize the Flint project in the given directory
);

pub fn main(io: std.Io, gpa: std.mem.Allocator, iter_start: std.process.Args.Iterator) !void {
    var iter: std.process.Args.Iterator = iter_start;

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;
    _ = stderr;

    var diag = clap.Diagnostic{};
    var res = try clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    });
    defer res.deinit();
    if (res.args.help != 0) {
        try printHelp(stdout);
        return;
    }

    const root: std.Io.Dir =
        if (res.positionals[0]) |dir|
            try std.Io.Dir.cwd().openDir(io, dir, .{})
        else
            std.Io.Dir.cwd();
    if (root.openFile(io, "flint.toml", .{})) |file| {
        // Don't change the file if it already exists
        file.close(io);
    } else |err| switch (err) {
        error.FileNotFound => {
            // Create file and write to it if it exists
            const file_flint_toml = try root.createFile(io, "flint.toml", .{});
            var writer_flint_toml = file_flint_toml.writer(io, &.{});
            const flint_toml = &writer_flint_toml.interface;
            try flint_toml.writeAll(
                \\# The configuration is applied project-wide across all parts of the Flint toolchain.
                \\# [config]
                \\# indentation = 4
                \\
                \\# To depend on other Flint libraries you can use the 'flint' kind, for example the standard
                \\# library. Extern dependencies can be used in Flint through 'use Std'. To use dependencies
                \\# which are not written in Flint, you need to set the 'kind' to the specific Interop Module
                \\# like 'fip-c' for C dependencies.
                \\[Std]
                \\kind = "flint"
                \\url = "https://github.com/flint-lang/std"
                \\tag = "v0.4.2"
                \\hash = "TODO"
                \\
            );
        },
        else => return err,
    }

    try root.createDir(io, "src", .default_dir);
    if (root.openFile(io, "src/main.ft", .{})) |file| {
        // Don't change the file if it already exists
        file.close(io);
    } else |err| switch (err) {
        error.FileNotFound => {
            // Create file and write to it if it exists
            const file_main_ft = try root.createFile(io, "src/main.ft", .{});
            var main_ft_writer = file_main_ft.writer(io, &.{});
            const main_ft = &main_ft_writer.interface;
            try main_ft.writeAll(
                \\use Core.print
                \\
                \\def main():
                \\    print("Hello, World!\n");
                \\
            );
        },
        else => return err,
    }
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: flint init [<dir>]
        \\
        \\  Initializes a new Flint project in the given directory. If no directory is provided a new project
        \\  will be created in the curent working directory instead.
        \\
        \\Options:
        \\
    );
    try clap.help(writer, clap.Help, &params, .{
        .indent = 2,
        .spacing_between_parameters = 0,
        .description_indent = 4,
        .description_on_new_line = false,
        .max_width = 100,
    });
}
