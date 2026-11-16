const std = @import("std");
const clap = @import("clap");

const net = @import("net.zig");
const extract = @import("extract.zig");

const State = @import("State.zig");

pub const Triple = struct {
    arch: std.Target.Cpu.Arch = .x86_64,
    os: std.Target.Os.Tag = .linux,
    abi: std.Target.Abi = .gnu,

    pub const MAX_LEN = 19;

    pub const x86_64_windows_gnu: Triple = .{ .arch = .x86_64, .os = .windows, .abi = .gnu };
    pub const x86_64_windows_msvc: Triple = .{ .arch = .x86_64, .os = .windows, .abi = .msvc };
    pub const x86_64_linux_gnu: Triple = .{ .arch = .x86_64, .os = .linux, .abi = .gnu };
    pub const x86_64_linux_musl: Triple = .{ .arch = .x86_64, .os = .linux, .abi = .musl };

    pub fn equals(self: Triple, other: Triple) bool {
        return self.arch == other.arch and
            self.os == other.os and
            self.abi == other.abi;
    }

    pub fn toString(self: Triple, allocator: std.mem.Allocator) ![]const u8 {
        return try allocator.print("{s}-{s}-{s}", .{
            @tagName(self.arch),
            @tagName(self.os),
            @tagName(self.abi),
        });
    }
};

const supported_triples = [_]Triple{
    Triple.x86_64_windows_gnu,
    Triple.x86_64_windows_msvc,
    Triple.x86_64_linux_gnu,
    Triple.x86_64_linux_musl,
};

const Commands = enum {
    help,
    list,
    install,
    remove,
};
const parsers = .{
    .command = clap.parsers.enumeration(Commands),
    .triple = clap.parsers.string,
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit
    \\<command>     The command to execute
);
const triple_params = clap.parseParamsComptime(
    \\<triple>
);

pub fn main(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    toolchain_path: []const u8,
    iter_start: std.process.Args.Iterator,
) !u8 {
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
    const triple: Triple = switch (command) {
        .help, .list => .{},
        else => blk: {
            var triple_res = try clap.parseEx(clap.Help, &triple_params, parsers, &iter, .{
                .diagnostic = &diag,
                .allocator = gpa,
                .terminating_positional = 0,
            });
            defer triple_res.deinit();

            const triple_str = triple_res.positionals[0] orelse {
                std.log.err("Missing required argument <triple> for subcommand '{s}'", .{@tagName(command)});
                try printHelp(stderr);
                return 1;
            };
            var iter_dash = std.mem.splitScalar(u8, triple_str, '-');
            const arch_str = iter_dash.next() orelse {
                std.log.err("Malformed target triple: '{s}'", .{triple_str});
                try printHelp(stderr);
                return 1;
            };
            const arch = std.meta.stringToEnum(std.Target.Cpu.Arch, arch_str) orelse {
                std.log.err("Malformed 'arch' of triple: '{s}'", .{arch_str});
                try printHelp(stderr);
                return 1;
            };
            const os_str = iter_dash.next() orelse {
                std.log.err("Malformed target triple: '{s}'", .{triple_str});
                try printHelp(stderr);
                return 1;
            };
            const os = std.meta.stringToEnum(std.Target.Os.Tag, os_str) orelse {
                std.log.err("Malformed 'os' of triple: '{s}'", .{os_str});
                try printHelp(stderr);
                return 1;
            };
            const abi_str = iter_dash.next() orelse {
                std.log.err("Malformed target triple: '{s}'", .{triple_str});
                try printHelp(stderr);
                return 1;
            };
            const abi = std.meta.stringToEnum(std.Target.Abi, abi_str) orelse {
                std.log.err("Malformed 'abi' of triple: '{s}'", .{abi_str});
                try printHelp(stderr);
                return 1;
            };
            if (iter_dash.next() != null) {
                std.log.err("Malformed target triple: '{s}'", .{triple_str});
                try printHelp(stderr);
                return 1;
            }

            const tr: Triple = .{
                .arch = arch,
                .os = os,
                .abi = abi,
            };
            for (supported_triples) |supported| {
                if (supported.equals(tr)) {
                    break;
                }
            } else {
                std.log.err("Target triple '{s}' is not supported. Run 'flint target list' to list supported triples.", .{triple_str});
                return 1;
            }

            break :blk tr;
        },
    };
    return switch (command) {
        .help => blk: {
            try printHelp(stdout);
            break :blk 0;
        },
        .list => {
            try stdout.writeAll("Available targets:\n");
            for (supported_triples, 1..) |supported, next| {
                if (next < supported_triples.len) {
                    try stdout.writeAll(" ├─ ");
                } else {
                    try stdout.writeAll(" └─ ");
                }
                const supported_str = try supported.toString(gpa);
                defer gpa.free(supported_str);
                try stdout.print("{[str]s:<[width]}", .{ .str = supported_str, .width = Triple.MAX_LEN });
                for ((try State.get(io, gpa, arena, toolchain_path)).installed_targets) |installed| {
                    if (supported.equals(installed)) {
                        try stdout.writeAll(" [installed]");
                    }
                }
                try stdout.writeAll("\n");
            }
            return 0;
        },
        .install => {
            for ((try State.get(io, gpa, arena, toolchain_path)).installed_targets) |target| {
                if (target.equals(triple)) {
                    std.log.info("Target is already installed, exiting...", .{});
                    return 0;
                }
            }
            if (triple.equals(Triple.x86_64_windows_gnu)) {
                try installTarget__x86_64_windows_gnu(io, gpa, toolchain_path);
            } else if (triple.equals(Triple.x86_64_windows_msvc)) {
                try installTarget__x86_64_windows_msvc(io, gpa, toolchain_path);
            } else if (triple.equals(Triple.x86_64_linux_gnu)) {
                installTarget__x86_64_linux_gnu();
            } else if (triple.equals(Triple.x86_64_linux_musl)) {
                try installTarget__x86_64_linux_musl(io, gpa, toolchain_path);
            }
            try State.addTargetInstalled(io, gpa, toolchain_path, triple);
            const triple_str = try triple.toString(gpa);
            defer gpa.free(triple_str);
            std.log.info("Installed target '{s}' successfully", .{triple_str});
            return 0;
        },
        .remove => {
            try State.removeTargetInstalled(io, gpa, arena, toolchain_path, triple);
            return 0;
        },
    };
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: flint target <command>
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
        \\  list                            List all available and installed targets
        \\  install <triple>                Install a specific target <triple>
        \\  remove <triple>                 Remove a specific target <triple>
        \\
    );
    try writer.flush();
}

fn installTarget__x86_64_windows_gnu(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !void {
    try installTargetFromArchive(
        io,
        allocator,
        toolchain_path,
        &.{
            .name = "x86_64-windows-gnu",
            .archive_filename = "x86_64-w64-mingw32-cross.tgz",
            .url = "https://github.com/musl-cc/musl.cc/releases/download/v0.0.1/x86_64-w64-mingw32-cross.tgz",
            .shasum = "6130e6b463742bdabe1ea53f7267c1cfb0f2902f50774b6c766d19776c419488",
            .needed_files = &.{
                // MinGW startup
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "crt2.o" } },

                // GCC startup / ending
                .{ .src = &.{ "lib", "gcc", "x86_64-w64-mingw32", "11.2.1", "crtbegin.o" } },
                .{ .src = &.{ "lib", "gcc", "x86_64-w64-mingw32", "11.2.1", "crtend.o" } },

                // GCC runtime
                .{ .src = &.{ "lib", "gcc", "x86_64-w64-mingw32", "11.2.1", "libgcc.a" } },
                .{ .src = &.{ "lib", "gcc", "x86_64-w64-mingw32", "11.2.1", "libgcc_eh.a" } },

                // MinGW runtime
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libmingw32.a" } },
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libmoldname.a" } },
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libmingwex.a" } },
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libmsvcrt.a" } },

                // Windows API imports
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libkernel32.a" } },
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libadvapi32.a" } },
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libshell32.a" } },
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libuser32.a" } },
                .{ .src = &.{ "x86_64-w64-mingw32", "lib", "libmingwthrd.a" } },
            },
            .type = .{ .tar_gz = .{ .strip_components = 1 } },
        },
    );
}

fn installTarget__x86_64_windows_msvc(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !void {
    try installTargetFromArchive(
        io,
        allocator,
        toolchain_path,
        &.{
            .name = "x86_64-windows-msvc",
            .archive_filename = "windows-sdk.nupkg",
            .url = "https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.cpp.x64/10.0.26100.9457/microsoft.windows.sdk.cpp.x64.10.0.26100.9457.nupkg",
            .shasum = "52bd17c63d3b6d268f385c358f34d0eb595b9c1deb3273855abd2ec5c095d132",
            .needed_files = &.{
                .{ .src = &.{ "c", "um", "x64", "kernel32.Lib" }, .dest = "kernel32.lib" },
                .{ .src = &.{ "c", "ucrt", "x64", "ucrt.lib" } },
                .{ .src = &.{ "c", "ucrt", "x64", "libucrt.lib" } },
            },
            .type = .zip,
        },
    );

    const msvc_version = "14.50.35717";
    try installTargetFromArchive(
        io,
        allocator,
        toolchain_path,
        &.{
            .name = "x86_64-windows-msvc",
            .archive_filename = "msvc-crt-x64-desktop.vsix",
            .url = "https://download.visualstudio.microsoft.com/download/pr/4cb7a450-4979-4d07-89e7-6613722fc25e/f538fed4fbf0fff460fa0a35f179319586d24c61804ab5d9780707cfd6353556/Microsoft.VC.14.50.18.0.CRT.x64.Desktop.base.vsix",
            .shasum = "f538fed4fbf0fff460fa0a35f179319586d24c61804ab5d9780707cfd6353556",
            .needed_files = &.{
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "libcmt.lib" } },
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "libvcruntime.lib" } },
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "libcpmt.lib" } },
            },
            .type = .zip,
        },
    );
    try installTargetFromArchive(
        io,
        allocator,
        toolchain_path,
        &.{
            .name = "x86_64-windows-msvc",
            .archive_filename = "msvc-crt-x64-store.vsix",
            .url = "https://download.visualstudio.microsoft.com/download/pr/4cb7a450-4979-4d07-89e7-6613722fc25e/ba895895ded7143f953a4ca0d6f0505df1844fdd138f9a18b61c395322ad11b3/Microsoft.VC.14.50.18.0.CRT.x64.Store.base.vsix",
            .shasum = "ba895895ded7143f953a4ca0d6f0505df1844fdd138f9a18b61c395322ad11b3",
            .needed_files = &.{
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "msvcrt.lib" } },
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "vcruntime.lib" } },
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "msvcprt.lib" } },
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "oldnames.lib" } },
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "legacy_stdio_definitions.lib" } },
                .{ .src = &.{ "Contents", "VC", "Tools", "MSVC", msvc_version, "lib", "x64", "legacy_stdio_wide_specifiers.lib" } },
            },
            .type = .zip,
        },
    );
}

fn installTarget__x86_64_linux_gnu() void {
    std.log.debug("The 'x86_64-linux-gnu' target is not yet implemented", .{});
}

fn installTarget__x86_64_linux_musl(io: std.Io, allocator: std.mem.Allocator, toolchain_path: []const u8) !void {
    try installTargetFromArchive(
        io,
        allocator,
        toolchain_path,
        &.{
            .name = "x86_64-linux-musl",
            .archive_filename = "x86_64-linux-musl-cross.tgz",
            .url = "https://github.com/musl-cc/musl.cc/releases/download/v0.0.1/x86_64-linux-musl-cross.tgz",
            .shasum = "c5d410d9f82a4f24c549fe5d24f988f85b2679b452413a9f7e5f7b956f2fe7ea",
            .needed_files = &.{
                .{ .src = &.{ "x86_64-linux-musl", "lib", "libc.so" } },
                .{ .src = &.{ "x86_64-linux-musl", "lib", "libc.a" } },
                .{ .src = &.{ "x86_64-linux-musl", "lib", "Scrt1.o" } },
                .{ .src = &.{ "x86_64-linux-musl", "lib", "crt1.o" } },
                .{ .src = &.{ "x86_64-linux-musl", "lib", "crti.o" } },
                .{ .src = &.{ "x86_64-linux-musl", "lib", "crtn.o" } },
                .{ .src = &.{ "lib", "gcc", "x86_64-linux-musl", "11.2.1", "libgcc.a" } },
                .{ .src = &.{ "lib", "gcc", "x86_64-linux-musl", "11.2.1", "libgcc_eh.a" } },
            },
            .type = .{ .tar_gz = .{ .strip_components = 1 } },
        },
    );
}

const InstallTargetFromArchiveOptions = struct {
    name: []const u8,
    archive_filename: []const u8,
    url: []const u8,
    shasum: []const u8,
    needed_files: []const struct {
        src: []const []const u8,
        /// The name of the file to put into the flat target directory, if a file needs to be renamed
        /// When this is 'null' then just the filename of 'src' is used
        dest: ?[]const u8 = null,
    },

    /// The archive type + extra options for that type
    type: union(enum) {
        tar_gz: struct {
            strip_components: u32 = 1,
        },
        zip: void,
    },
};

fn installTargetFromArchive(
    io: std.Io,
    allocator: std.mem.Allocator,
    toolchain_path: []const u8,
    options: *const InstallTargetFromArchiveOptions,
) !void {
    const sep = std.fs.path.sep;
    const targets_dir_path: []const u8 = try allocator.print("{s}{c}targets", .{ toolchain_path, sep });
    defer allocator.free(targets_dir_path);
    std.Io.Dir.cwd().createDir(io, targets_dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const target_dir_path: []const u8 = try allocator.print("{s}{c}{s}", .{ targets_dir_path, sep, options.name });
    defer allocator.free(target_dir_path);
    std.Io.Dir.cwd().createDir(io, target_dir_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // 1. Download
    const archive_path: []const u8 = try allocator.print("{s}{c}{s}", .{ target_dir_path, sep, options.archive_filename });
    defer allocator.free(archive_path);
    try net.downloadFile(io, allocator, options.url, archive_path);

    // 2. Verify shasum
    try net.checkFileIntegrity(io, allocator, archive_path, options.shasum);

    // 3. Extract
    const extracted_path: []const u8 = try allocator.print("{s}{c}{s}-extracted", .{
        target_dir_path,
        sep,
        options.archive_filename,
    });
    defer allocator.free(extracted_path);
    try std.Io.Dir.cwd().deleteTree(io, extracted_path);
    try std.Io.Dir.cwd().createDir(io, extracted_path, .default_dir);
    switch (options.type) {
        .tar_gz => |tar_gz| {
            try extract.tarGz(io, allocator, archive_path, extracted_path, tar_gz.strip_components);
        },
        .zip => {
            try extract.zip(io, archive_path, extracted_path);
        },
    }

    // 4. Copy needed libs
    const dest_dir: std.Io.Dir = try std.Io.Dir.cwd().openDir(io, target_dir_path, .{});
    defer dest_dir.close(io);
    for (options.needed_files) |needed_file| {
        const dest_path: []const u8 =
            if (needed_file.dest) |dest|
                try allocator.print("{s}{c}{s}", .{ target_dir_path, sep, dest })
            else blk: {
                const filename = needed_file.src[needed_file.src.len - 1];
                break :blk try allocator.print("{s}{c}{s}", .{ target_dir_path, sep, filename });
            };
        defer allocator.free(dest_path);

        var source_path = extracted_path;
        for (needed_file.src, 0..) |subdir, i| {
            const new_subdir = try allocator.print("{s}{c}{s}", .{ source_path, sep, subdir });
            if (i > 0) {
                allocator.free(source_path);
            }
            source_path = new_subdir;
        }
        defer allocator.free(source_path);

        std.Io.Dir.cwd().copyFile(source_path, dest_dir, dest_path, io, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.err("Cannot copy file '{s}'", .{source_path});
                return err;
            },
            else => return err,
        };
    }

    // 5. Delete downloaded .tgz and temp dir
    try std.Io.Dir.cwd().deleteFile(io, archive_path);
    try std.Io.Dir.cwd().deleteTree(io, extracted_path);
}
