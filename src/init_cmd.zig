const std = @import("std");
const clap = @import("clap");

const parsers = .{
    .dir = clap.parsers.string,
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit.
    \\<dir>         Initialize the Flint project in the given directory
);

pub fn main(io: std.Io, gpa: std.mem.Allocator, iter_start: std.process.Args.Iterator) !u8 {
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
        return 0;
    }

    const root: std.Io.Dir =
        if (res.positionals[0]) |dir|
            std.Io.Dir.cwd().openDir(io, dir, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    std.log.err("The passed-in directory '{s}' does not exist. Use '--help' for more information", .{dir});
                    return 1;
                },
                else => return err,
            }
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
                \\[config]
                \\indentation = 4
                \\# The 'main' file is passed to the Flint compiler when calling 'flint build'
                \\main = "src/main.ft"
                \\# The 'lib' file acts as the entry point when this project is used as a library
                \\lib = "src/lib.ft"
                \\
                \\# To depend on other Flint libraries you can use the 'flint' kind, for example the standard
                \\# library. Extern dependencies can be used in Flint through 'use Std'. To use dependencies
                \\# which are not written in Flint, you need to set the 'kind' to the specific Interop Module
                \\# like 'fip-c' for C dependencies.
                \\[Std]
                \\kind = "flint"
                \\url = "https://github.com/flint-lang/std"
                \\rev = "4715a84bbfe3e138c4de7af2bf4d9994df0c9df5"
                \\sha256 = "61a4c8bf18d3e3f49875114b08252810c1dd9cdc8e8d8f1dfed9191bb377fd7c"
                \\
            );
        },
        else => return err,
    }

    root.createDir(io, "src", .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    if (root.openFile(io, "src/main.ft", .{})) |file| {
        file.close(io);
    } else |err| switch (err) {
        error.FileNotFound => try root.writeFile(io, .{
            .sub_path = "src/main.ft",
            .data =
            \\use "lib.ft" as lib
            \\
            \\def main():
            \\    lib.greet();
            \\
            ,
        }),
        else => return err,
    }
    if (root.openFile(io, "src/lib.ft", .{})) |file| {
        file.close(io);
    } else |err| switch (err) {
        error.FileNotFound => try root.writeFile(io, .{
            .sub_path = "src/lib.ft",
            .data =
            \\use Core.print
            \\
            \\def greet():
            \\    print("Hello from lib!\n");
            \\
            ,
        }),
        else => return err,
    }
    return 0;
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: flint init [<dir>]
        \\
        \\  Initializes a new Flint project in the given directory. If no directory is provided a new project
        \\  will be created in the current working directory instead.
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
