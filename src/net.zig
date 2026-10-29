const std = @import("std");
const builtin = @import("builtin");

/// Download `url` into `file_path`. Streams body, optional decompress, TTY progress on stderr.
pub fn downloadFile(io: std.Io, allocator: std.mem.Allocator, url: []const u8, file_path: []const u8) !void {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var req = try client.request(.GET, uri, .{});
    defer req.deinit();
    try req.sendBodiless();

    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);

    const status = response.head.status;
    const content_length = response.head.content_length;
    const content_encoding = response.head.content_encoding;

    if (status.class() != .success) {
        std.log.err("download failed: {d} {s}", .{
            @intFromEnum(status),
            status.phrase() orelse "unknown",
        });
        return error.HttpRequestFailed;
    }

    // Overwrite if present
    std.Io.Dir.cwd().deleteFile(io, file_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    var file = try std.Io.Dir.cwd().createFile(io, file_path, .{ .truncate = true });
    defer file.close(io);
    errdefer std.Io.Dir.cwd().deleteFile(io, file_path) catch {};

    var file_buf: [64 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &file_buf);

    const decompress_buffer: []u8 = switch (content_encoding) {
        .identity => &.{},
        .zstd => try allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (decompress_buffer.len != 0) allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    var progress = Progress.init(
        io,
        &stderr_writer.interface,
        std.fs.path.basename(file_path),
        if (content_encoding == .identity) content_length else null,
    );
    defer progress.deinit();
    errdefer progress.clear();

    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const n = reader.readSliceShort(&buffer) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr().?,
        };
        if (n == 0) break;

        try file_writer.interface.writeAll(buffer[0..n]);
        progress.add(n);
    }

    try file_writer.interface.flush();
    progress.finish();
}

const Progress = struct {
    io: std.Io,
    writer: *std.Io.Writer,
    label: []const u8,
    total: ?u64,
    downloaded: u64 = 0,
    start_ns: i96,
    last_draw_ns: i96,
    last_percent: u64 = 999,
    prev_line_len: usize = 0,
    enabled: bool,
    drawn: bool = false,
    cursor_hidden: bool = false,

    const min_bar_width: usize = 10;
    const draw_interval_ns: i96 = 150 * std.time.ns_per_ms;
    const min_draw_size: u64 = 256 * 1024;
    const fallback_columns: usize = 80;
    const suffix_budget: usize = 48;

    fn init(io: std.Io, writer: *std.Io.Writer, label: []const u8, total: ?u64) Progress {
        if (builtin.os.tag == .windows) {
            std.Io.File.stderr().enableAnsiEscapeCodes(io) catch {};
        }
        const now = std.Io.Clock.now(.awake, io).nanoseconds;
        return .{
            .io = io,
            .writer = writer,
            .label = label,
            .total = total,
            .start_ns = now,
            .last_draw_ns = now,
            .enabled = std.Io.File.stderr().isTty(io) catch false,
        };
    }

    fn deinit(self: *Progress) void {
        self.showCursor();
    }

    fn hideCursor(self: *Progress) void {
        if (!self.enabled or self.cursor_hidden) {
            return;
        }
        self.writer.writeAll("\x1b[?25l") catch {};
        self.writer.flush() catch {};
        self.cursor_hidden = true;
    }

    fn showCursor(self: *Progress) void {
        if (!self.cursor_hidden) {
            return;
        }
        self.writer.writeAll("\x1b[?25h") catch {};
        self.writer.flush() catch {};
        self.cursor_hidden = false;
    }

    fn terminalColumns(self: *const Progress) usize {
        _ = self;
        if (builtin.os.tag == .linux) {
            const stdout_fd: std.posix.fd_t = std.posix.STDERR_FILENO;
            var wsz: std.posix.winsize = std.mem.zeroes(std.posix.winsize);
            const rc = std.posix.system.ioctl(stdout_fd, std.posix.T.IOCGWINSZ, @intFromPtr(&wsz));
            if (rc == 0 and wsz.col >= 40) {
                return wsz.col;
            }
        }
        return fallback_columns;
    }

    fn add(self: *Progress, bytes: usize) void {
        self.downloaded += bytes;
        if (!self.enabled) {
            return;
        }

        const now = std.Io.Clock.now(.awake, self.io).nanoseconds;

        if (!self.drawn) {
            const size = self.total orelse self.downloaded;
            if (size < min_draw_size) {
                return;
            }
            self.hideCursor();
        } else if (now - self.last_draw_ns < draw_interval_ns) {
            if (self.total) |total| {
                if (total == 0) {
                    return;
                }
                const pct: u64 = @intFromFloat(
                    @min(100.0, @as(f64, @floatFromInt(self.downloaded)) * 100.0 / @as(f64, @floatFromInt(total))),
                );
                if (pct == self.last_percent) {
                    return;
                }
            } else return;
        }

        self.last_draw_ns = now;
        self.draw(now) catch {};
    }

    fn draw(self: *Progress, now: i96) !void {
        const cols = self.terminalColumns();
        const elapsed_ns: u64 = @intCast(@max(now - self.start_ns, 1));
        const speed_bps = @as(f64, @floatFromInt(self.downloaded)) *
            @as(f64, @floatFromInt(std.time.ns_per_s)) /
            @as(f64, @floatFromInt(elapsed_ns));

        const prefix = "Downloading ";
        const prefix_len = prefix.len + self.label.len + 1;
        const bar_width = @max(min_bar_width, cols -| prefix_len -| 2 -| suffix_budget);

        var line_buf: [512]u8 = undefined;
        var pos: usize = 0;

        try appendSlice(&line_buf, &pos, prefix);
        try appendSlice(&line_buf, &pos, self.label);
        try appendSlice(&line_buf, &pos, " ");

        if (self.total) |total| {
            const ratio = if (total == 0) 1.0 else @min(
                1.0,
                @as(f64, @floatFromInt(self.downloaded)) / @as(f64, @floatFromInt(total)),
            );
            const filled: usize = @intFromFloat(ratio * @as(f64, @floatFromInt(bar_width)));
            const percent: u64 = @intFromFloat(ratio * 100.0);
            self.last_percent = percent;

            try appendSlice(&line_buf, &pos, "[");
            try appendByteN(&line_buf, &pos, '#', filled);
            try appendByteN(&line_buf, &pos, '-', bar_width - filled);
            try appendSlice(&line_buf, &pos, "] ");
            try appendFmt(&line_buf, &pos, "{d:3}%  ", .{percent});
            try appendBinarySize(&line_buf, &pos, self.downloaded);
            try appendSlice(&line_buf, &pos, "/");
            try appendBinarySize(&line_buf, &pos, total);

            if (self.downloaded > 0 and percent < 100) {
                const remaining = total -| self.downloaded;
                const eta_s: u64 = @intFromFloat(
                    @as(f64, @floatFromInt(remaining)) / @max(speed_bps, 1.0),
                );
                try appendSlice(&line_buf, &pos, "  ETA ");
                try appendEta(&line_buf, &pos, eta_s);
            } else {
                try appendSlice(&line_buf, &pos, "  ETA 00:00");
            }
        } else {
            const phase: usize = @intCast(@divTrunc(elapsed_ns, @as(u64, @intCast(draw_interval_ns))) % bar_width);
            try appendSlice(&line_buf, &pos, "[");
            var i: usize = 0;
            while (i < bar_width) : (i += 1) {
                try appendByteN(&line_buf, &pos, if (i == phase) @as(u8, '>') else '-', 1);
            }
            try appendSlice(&line_buf, &pos, "] ");
            try appendBinarySize(&line_buf, &pos, self.downloaded);
        }

        try appendSlice(&line_buf, &pos, "  ");
        try appendSpeed(&line_buf, &pos, speed_bps);

        const line = line_buf[0..pos];
        const w = self.writer;

        try w.writeAll("\r");
        try w.writeAll(line);
        if (self.prev_line_len > line.len) {
            try w.splatByteAll(' ', self.prev_line_len - line.len);
        }
        try w.flush();

        self.prev_line_len = line.len;
        self.drawn = true;
    }

    fn finish(self: *Progress) void {
        if (!self.enabled or !self.drawn) {
            self.showCursor();
            return;
        }
        const now = std.Io.Clock.now(.awake, self.io).nanoseconds;
        self.draw(now) catch {};
        self.writer.writeByte('\n') catch {};
        self.writer.flush() catch {};
        self.showCursor();
    }

    fn clear(self: *Progress) void {
        if (!self.enabled or !self.drawn) {
            self.showCursor();
            return;
        }
        self.writer.writeAll("\r\x1b[K") catch {};
        self.writer.flush() catch {};
        self.showCursor();
        self.drawn = false;
        self.prev_line_len = 0;
    }
};

fn appendSlice(buf: []u8, pos: *usize, slice: []const u8) !void {
    if (pos.* + slice.len > buf.len) {
        return error.NoSpaceLeft;
    }
    @memcpy(buf[pos.*..][0..slice.len], slice);
    pos.* += slice.len;
}

fn appendByteN(buf: []u8, pos: *usize, byte: u8, n: usize) !void {
    if (pos.* + n > buf.len) {
        return error.NoSpaceLeft;
    }
    @memset(buf[pos.*..][0..n], byte);
    pos.* += n;
}

fn appendFmt(buf: []u8, pos: *usize, comptime fmt: []const u8, args: anytype) !void {
    const written = try std.fmt.bufPrint(buf[pos.*..], fmt, args);
    pos.* += written.len;
}

fn appendBinarySize(buf: []u8, pos: *usize, bytes: u64) !void {
    const kib: f64 = 1024.0;
    const mib: f64 = kib * 1024.0;
    const gib: f64 = mib * 1024.0;
    const b: f64 = @floatFromInt(bytes);
    if (b >= gib) {
        try appendFmt(buf, pos, "{d:.1}GiB", .{b / gib});
    } else if (b >= mib) {
        try appendFmt(buf, pos, "{d:.1}MiB", .{b / mib});
    } else if (b >= kib) {
        try appendFmt(buf, pos, "{d:.1}KiB", .{b / kib});
    } else {
        try appendFmt(buf, pos, "{d}B", .{bytes});
    }
}

fn appendSpeed(buf: []u8, pos: *usize, bps: f64) !void {
    const kib = 1024.0;
    const mib = kib * 1024.0;
    if (bps >= mib) {
        try appendFmt(buf, pos, "{d:.1} MiB/s", .{bps / mib});
    } else if (bps >= kib) {
        try appendFmt(buf, pos, "{d:.1} KiB/s", .{bps / kib});
    } else {
        try appendFmt(buf, pos, "{d:.0} B/s", .{bps});
    }
}

fn appendEta(buf: []u8, pos: *usize, seconds: u64) !void {
    const s = seconds % 60;
    const m = (seconds / 60) % 60;
    const h = seconds / 3600;
    if (h > 0) {
        try appendFmt(buf, pos, "{d:0>2}:{d:0>2}:{d:0>2}", .{ h, m, s });
    } else {
        try appendFmt(buf, pos, "{d:0>2}:{d:0>2}", .{ m, s });
    }
}
