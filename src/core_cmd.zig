const std = @import("std");
const clap = @import("clap");

pub fn main(io: std.Io, gpa: std.mem.Allocator, iter_start: std.process.Args.Iterator) !void {
    _ = gpa;

    const iter: std.process.Args.Iterator = iter_start;
    _ = iter;

    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;
    _ = stdout;
    _ = stderr;
}
