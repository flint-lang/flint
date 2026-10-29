const std = @import("std");

pub fn downloadFile(io: std.Io, allocator: std.mem.Allocator, url: []const u8, file_path: []const u8) !void {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var file = try std.Io.Dir.cwd().createFile(io, file_path, .{ .truncate = true });
    defer file.close(io);

    var file_buf: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &file_buf);

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &file_writer.interface,
    });
    try file_writer.interface.flush();

    if (result.status.class() != .success) {
        std.log.err("download failed: {d} {s}", .{
            @intFromEnum(result.status),
            result.status.phrase() orelse "unknown",
        });
        return error.HttpRequestFailed;
    }
}
