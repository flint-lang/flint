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

pub fn tarGz(
    io: std.Io,
    allocator: std.mem.Allocator,
    tar_gz_path: []const u8,
    extract_to: []const u8,
    strip_level: u32,
) !void {
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
    var diagnostics: std.tar.Diagnostics = .{
        .allocator = allocator,
    };
    defer diagnostics.deinit();

    try std.tar.extract(io, target_dir, &decompressor.reader, .{
        .strip_components = strip_level,
        .diagnostics = &diagnostics,
    });

    for (diagnostics.errors.items) |diagnostic| {
        switch (diagnostic) {
            .unsupported_file_type => |info| {
                std.log.warn(
                    "Skipping unsupported TAR entry '{s}' (type: {s})",
                    .{ info.file_name, @tagName(info.file_type) },
                );
            },
            else => {
                std.log.err("extract.tarGz: {any}", .{diagnostic});
            },
        }
    }

    std.log.info("Successfully extracted archive to {s}.", .{extract_to});
}

pub fn tarZst(
    io: std.Io,
    allocator: std.mem.Allocator,
    tar_zst_path: []const u8,
    extract_to: []const u8,
    strip_level: u32,
) !void {
    // Open the Zstandard-compressed TAR archive.
    const zst_file = try std.Io.Dir.cwd().openFile(io, tar_zst_path, .{});
    defer zst_file.close(io);

    // Create the input reader.
    var reader_buffer: [8192]u8 = @splat(0);
    var file_reader = zst_file.reader(io, &reader_buffer);

    // Zstandard needs a window buffer plus space for one maximum-sized block.
    const decompress_buffer_len: usize =
        std.compress.zstd.default_window_len +
        std.compress.zstd.block_size_max;

    const decompress_buffer = try allocator.alloc(u8, decompress_buffer_len);
    defer allocator.free(decompress_buffer);

    var decompressor = std.compress.zstd.Decompress.init(
        &file_reader.interface,
        decompress_buffer,
        .{},
    );

    // Open the destination directory.
    const target_dir = try std.Io.Dir.cwd().openDir(io, extract_to, .{});
    defer target_dir.close(io);

    std.log.info("Extracting Zst TAR archive to {s}, this may take a while...", .{
        extract_to,
    });

    var diagnostics: std.tar.Diagnostics = .{
        .allocator = allocator,
    };
    defer diagnostics.deinit();

    try std.tar.extract(io, target_dir, &decompressor.reader, .{
        .strip_components = strip_level,
        .diagnostics = &diagnostics,
    });

    // Do not silently accept an incomplete sysroot.
    for (diagnostics.errors.items) |diagnostic| {
        switch (diagnostic) {
            .unable_to_create_sym_link => |info| {
                std.log.err(
                    "Cannot create symlink '{s}' -> '{s}': {s}",
                    .{
                        info.file_name,
                        info.link_name,
                        @errorName(info.code),
                    },
                );
            },
            .unable_to_create_file => |info| {
                std.log.err(
                    "Cannot create file '{s}': {s}",
                    .{ info.file_name, @errorName(info.code) },
                );
            },
            .unsupported_file_type => |info| {
                std.log.err(
                    "Unsupported TAR entry '{s}' (type: {s})",
                    .{ info.file_name, @tagName(info.file_type) },
                );
            },
            .components_outside_stripped_prefix => |info| {
                std.log.err(
                    "TAR entry is outside the stripped prefix: '{s}'",
                    .{info.file_name},
                );
            },
        }
    }

    if (diagnostics.errors.items.len != 0) {
        return error.TarExtractionDiagnostics;
    }

    std.log.info("Successfully extracted Zst TAR archive to {s}.", .{
        extract_to,
    });
}

pub fn zip(io: std.Io, zip_path: []const u8, extract_to: []const u8) !void {
    // Open the ZIP file.
    const zip_file = try std.Io.Dir.cwd().openFile(io, zip_path, .{});
    defer zip_file.close(io);

    // Create a file reader.
    var reader_buffer: [8192]u8 = @splat(0);
    var file_reader = zip_file.reader(io, &reader_buffer);

    // Open the extraction directory.
    var target_dir = try std.Io.Dir.cwd().openDir(io, extract_to, .{});
    defer target_dir.close(io);

    std.log.info("Extracting ZIP archive to {s}, this may take a while...", .{
        extract_to,
    });

    try std.zip.extract(target_dir, &file_reader, .{});

    std.log.info("Successfully extracted ZIP archive to {s}.", .{
        extract_to,
    });
}

pub fn conda(
    io: std.Io,
    allocator: std.mem.Allocator,
    conda_path: []const u8,
    extract_to: []const u8,
    strip_level: u32,
) !void {
    const cwd = std.Io.Dir.cwd();

    // Open the outer .conda ZIP container.
    const conda_file = try cwd.openFile(io, conda_path, .{});
    defer conda_file.close(io);

    var zip_reader_buffer: [8192]u8 = @splat(0);
    var zip_reader = conda_file.reader(io, &zip_reader_buffer);

    // Read the ZIP central directory.
    var iterator = try std.zip.Iterator.init(&zip_reader);

    // The package member is named pkg-<name>-<version>-<build>.tar.zst.
    var filename_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;

    // Extract the inner package TAR to a temporary file.
    const sep = std.fs.path.sep;
    const payload_path = try allocator.print(
        "{s}{c}.flint-conda-payload.tar.zst",
        .{ extract_to, sep },
    );
    defer allocator.free(payload_path);

    // Remove a stale temporary file from a previous interrupted installation.
    cwd.deleteFile(io, payload_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    // Always clean up the temporary payload, including on extraction errors.
    defer cwd.deleteFile(io, payload_path) catch {};

    var found_payload = false;

    while (try iterator.next()) |entry| {
        const member_name = try entry.getFilename(
            &zip_reader,
            &filename_buffer,
            .{},
        );

        // Ignore metadata.json and info-*.tar.zst.
        if (!std.mem.startsWith(u8, member_name, "pkg-")) continue;
        if (!std.mem.endsWith(u8, member_name, ".tar.zst")) continue;

        if (found_payload) {
            return error.MultipleCondaPackagePayloads;
        }

        std.log.info("Extracting conda payload: {s}", .{
            member_name,
        });

        {
            const payload_file = try cwd.createFile(
                io,
                payload_path,
                .{ .exclusive = true },
            );
            defer payload_file.close(io);

            var writer_buffer: [8192]u8 = @splat(0);
            var payload_writer = payload_file.writer(io, &writer_buffer);

            // Extract the ZIP member's contents without invoking an external tool.
            try entry.extractTo(
                &zip_reader,
                &payload_writer.interface,
            );

            try payload_writer.interface.flush();
        }

        found_payload = true;
        break;
    }

    if (!found_payload) {
        return error.CondaPackagePayloadNotFound;
    }

    // Decompress the inner Zstandard TAR and extract its filesystem tree.
    try tarZst(
        io,
        allocator,
        payload_path,
        extract_to,
        strip_level,
    );

    std.log.info("Successfully extracted conda package to {s}.", .{
        extract_to,
    });
}
