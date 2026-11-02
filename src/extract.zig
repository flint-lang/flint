const std = @import("std");

pub fn tarXz(io: std.Io, allocator: std.mem.Allocator, tar_xz_path: []const u8, extract_to: []const u8, strip_level: u32) !void {
    // Open the XZ file
    const xz_file: std.Io.File = try std.Io.Dir.cwd().openFile(io, tar_xz_path, .{});
    defer xz_file.close();

    // Create a file reader with a buffer
    var reader_buffer: [8192]u8 = @splat(0);
    var file_reader: std.Io.File.Reader = xz_file.reader(io, &reader_buffer);

    // Note: Decompression still needs dynamic allocation due to xz library requirements.
    // This is unavoidable for compressed data handling.
    var decompress_buffer: [8192]u8 = @splat(0);
    var decompressor: std.compress.xz.Decompress = .init(&file_reader.interface, allocator, &decompress_buffer);
    defer decompressor.deinit();

    var target_dir: std.Io.Dir = try std.Io.Dir.cwd().openDir(extract_to, .{});
    defer target_dir.close();

    std.log.info("Extracting archive to {s}, this may take a while...", .{extract_to});
    try std.tar.pipeToFileSystem(io, target_dir, &decompressor.reader, .{
        .strip_components = strip_level,
    });

    std.log.info("Successfully extracted archive to {s}.", .{extract_to});
}

pub fn tarGz(io: std.Io, tar_gz_path: []const u8, extract_to: []const u8, strip_level: u32) !void {
    // Open the GZ file
    const gz_file: std.Io.File = try std.Io.Dir.cwd().openFile(io, tar_gz_path, .{});
    defer gz_file.close(io);

    // Create a file reader with a buffer
    var reader_buffer: [8192]u8 = @splat(0);
    var file_reader: std.Io.File.Reader = gz_file.reader(io, &reader_buffer);

    // Window buffer required by flate (must be >= max_window_len when non-empty)
    var decompress_buffer: [std.compress.flate.max_window_len]u8 = @splat(0);
    var decompressor: std.compress.flate.Decompress = .init(
        &file_reader.interface,
        .gzip,
        &decompress_buffer,
    );

    var target_dir: std.Io.Dir = try std.Io.Dir.cwd().openDir(io, extract_to, .{});
    defer target_dir.close(io);

    std.log.info("Extracting archive to {s}, this may take a while...", .{extract_to});
    try std.tar.pipeToFileSystem(io, target_dir, &decompressor.reader, .{
        .strip_components = strip_level,
    });

    std.log.info("Successfully extracted archive to {s}.", .{extract_to});
}
