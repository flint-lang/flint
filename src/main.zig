const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");

const defines = @import("defines");

const net = @import("net.zig");
const fip_cmd = @import("fip_cmd.zig");
const target_cmd = @import("target_cmd.zig");
const init_cmd = @import("init_cmd.zig");
const fetch_cmd = @import("fetch_cmd.zig");
const build_cmd = @import("build_cmd.zig");

const Registry = @import("Registry.zig");
const State = @import("State.zig");

const SubCommand = enum {
    help,
    // Other toolchain-related commands
    fip,
    target,
    // Core commands
    list,
    install,
    update,
    upgrade,
    remove,
    @"switch",
    // Build-related commands
    init,
    fetch,
    build,
};
const parsers = .{
    .command = clap.parsers.enumeration(SubCommand),
    .version = clap.parsers.string,
};
const params = clap.parseParamsComptime(
    \\-h, --help    Display this help and exit
    \\-v, --version Display the version information and exit
    \\<command>     The command to execute
);
const version_params = clap.parseParamsComptime(
    \\<version>     The Flint version to manage
);

fn getToolchainPath(io: std.Io, allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => blk: {
            const localappdata = environ_map.get("LOCALAPPDATA") orelse {
                std.log.err("Failed to get environment variable '%LOCALAPPDATA%'", .{});
                return error.GetToolchainPathFailed;
            };
            const full_path = try std.fmt.allocPrint(allocator, "{s}\\Flint\\Toolchain", .{localappdata});
            try std.Io.Dir.cwd().createDirPath(io, full_path);
            break :blk full_path;
        },
        .linux => blk: {
            const full_path =
                if (environ_map.get("XDG_DATA_HOME")) |xdg_data_home|
                    try std.fmt.allocPrint(allocator, "{s}/flint", .{xdg_data_home})
                else if (environ_map.get("HOME")) |home|
                    try std.fmt.allocPrint(allocator, "{s}/.local/share/flint", .{home})
                else {
                    std.log.err("Failed to get either environment variable '$XDG_DATA_HOME' or '$HOME'", .{});
                    return error.GetToolchainPathFailed;
                };
            try std.Io.Dir.cwd().createDirPath(io, full_path);
            break :blk full_path;
        },
        else => @panic("Unsupported OS"),
    };
}

pub fn main(init: std.process.Init) !u8 {
    // Allocator when I need more stack-frames visible, for example when fixing memory leaks
    // var gpa: std.heap.DebugAllocator(.{
    //     .stack_trace_frames = 20,
    // }) = .init;
    // defer std.debug.assert(gpa.deinit() == .ok);
    // const allocator = gpa.allocator();
    const allocator = init.gpa;

    var stdin_reader = std.Io.File.stdin().reader(init.io, &.{});
    const stdin = &stdin_reader.interface;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(init.io, &.{});
    const stderr = &stderr_writer.interface;

    const toolchain_path = try getToolchainPath(init.io, allocator, init.environ_map);
    defer allocator.free(toolchain_path);

    defer Registry.deinit(allocator);
    defer State.deinit(allocator);

    var iter = try init.minimal.args.iterateAllocator(allocator);
    defer iter.deinit();

    _ = iter.next();

    var diag_clap = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, parsers, &iter, .{
        .diagnostic = &diag_clap,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch {
        std.log.err("Invalid <command>: {s}", .{init.minimal.args.vector[1]});
        try printHelp(stderr);
        return 1;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try printHelp(stdout);
        return 0;
    }
    if (res.args.version != 0) {
        try stdout.print("flint v{s} ({s}, {s})\n", .{ defines.version, defines.hash, defines.date });
        try stdout.flush();
        return 0;
    }

    const command = res.positionals[0] orelse {
        std.log.err("Missing required argument <command>", .{});
        try printHelp(stderr);
        return 1;
    };
    var version: []const u8 = switch (command) {
        .help, .fip, .target, .list, .update, .upgrade => &.{},
        .install, .remove, .@"switch" => blk: {
            var version_res = try clap.parseEx(clap.Help, &version_params, parsers, &iter, .{
                .diagnostic = &diag_clap,
                .allocator = allocator,
                .terminating_positional = 0,
            });
            defer version_res.deinit();
            const _version = version_res.positionals[0] orelse if (command == .install)
                try Registry.getNewestToolchainVersion(init.io, allocator, toolchain_path)
            else {
                std.log.err("Missing required argument <version> for '{s}' command", .{@tagName(command)});
                try printHelp(stderr);
                return 1;
            };

            if (command == .remove or command == .@"switch") {
                // We dont need to verify the version and consolidate the registry, as for these commands the information whether
                // they are installed at all is enough
                break :blk _version;
            }
            var iter_toolchain = (try Registry.get(init.io, allocator, toolchain_path)).toolchain.iterator();
            const version_found: bool = blk2: while (iter_toolchain.next()) |toolchain| {
                if (std.mem.eql(u8, toolchain.key_ptr.*, _version)) {
                    break :blk2 true;
                }
            } else false;
            if (!version_found) {
                std.log.err("Version '{s}' is not a known Flint versions.", .{_version});
                std.log.info("Execute 'flint list' to list all available versions.", .{});
                return 1;
            }

            break :blk _version;
        },
        .init, .fetch, .build => &.{},
    };
    var continuation: ?SubCommand = null;
    var active: ?[]const u8 = null;
    defer if (active) |a| {
        allocator.free(a);
    };
    sw: switch (command) {
        .help => {
            try printHelp(stdout);
            return 0;
        },
        .fip => return fip_cmd.main(init.io, allocator, iter),
        .target => return target_cmd.main(init.io, allocator, iter),
        .list => {
            var iter_toolchain = (try Registry.get(init.io, allocator, toolchain_path)).toolchain.iterator();
            try stdout.writeAll("Available Flint versions:\n");
            var current = iter_toolchain.next();
            while (current) |toolchain| {
                const next = iter_toolchain.next();
                if (next != null) {
                    try stdout.print(" ├─ {s}", .{toolchain.key_ptr.*});
                } else {
                    try stdout.print(" └─ {s}", .{toolchain.key_ptr.*});
                }
                for ((try State.get(init.io, allocator, toolchain_path)).toolchain_installed) |installed| {
                    if (std.mem.eql(u8, installed, toolchain.key_ptr.*)) {
                        try stdout.writeAll(" [installed]");
                        break;
                    }
                }
                if ((try State.get(init.io, allocator, toolchain_path)).toolchain_active) |a| {
                    if (std.mem.eql(u8, a, toolchain.key_ptr.*)) {
                        try stdout.writeAll(" [active]");
                    }
                }
                try stdout.writeByte('\n');
                current = next;
            }
            try stdout.flush();
            return 0;
        },
        .install => {
            // Check if the to-be-installed version is already installed
            const already_installed: bool = blk: for ((try State.get(init.io, allocator, toolchain_path)).toolchain_installed) |installed| {
                if (std.mem.eql(u8, installed, version)) {
                    break :blk true;
                }
            } else false;
            if (already_installed) {
                try stdout.print("Version '{s}' is already installed. Do you want to re-install it? [y/N] ", .{version});
                var out: [1]u8 = @splat(0);
                try stdin.readSliceAll(&out);
                switch (out[0]) {
                    'y', 'Y' => {},
                    'n', 'N', '\n' => return 0,
                    else => {
                        std.log.err("Expected one of 'y', 'Y', 'n' or 'N' but got '{c}'", .{out[0]});
                        return 1;
                    },
                }
            }
            const release = (try Registry.get(init.io, allocator, toolchain_path)).toolchain.get(version).?;
            var iter_artifacts = release.artifacts.iterator();
            const artifact: ?Registry.ToolchainRelease.PlatformArtifacts = blk: while (iter_artifacts.next()) |artifact| {
                var split_iterator = std.mem.splitScalar(u8, artifact.key_ptr.*, '-');
                const arch = blk2: {
                    const arch_str = split_iterator.next() orelse {
                        std.log.err("Artifact string does not start with architecture: {s}", .{artifact.key_ptr.*});
                        return 1;
                    };
                    break :blk2 std.meta.stringToEnum(std.Target.Cpu.Arch, arch_str) orelse {
                        std.log.err("Invalid architecture detected in registry: {s}", .{arch_str});
                        return 1;
                    };
                };
                const platform = blk2: {
                    const platform_str = split_iterator.next() orelse {
                        std.log.err("Artifact string does not end with platform: {s}", .{artifact.key_ptr.*});
                        return 1;
                    };
                    break :blk2 std.meta.stringToEnum(std.Target.Os.Tag, platform_str) orelse {
                        std.log.err("Invalid platform detected in registry: {s}", .{platform_str});
                        return 1;
                    };
                };
                std.debug.assert(split_iterator.next() == null);
                if (builtin.cpu.arch != arch) {
                    continue;
                }
                if (builtin.os.tag != platform) {
                    continue;
                }
                break :blk artifact.value_ptr.*;
            } else null;
            if (artifact == null) {
                std.log.err("Could not find suitable platform for this system: {s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag) });
                return 1;
            }
            const flintc = artifact.?.flintc;
            const fls = artifact.?.fls;

            const sep = std.Io.Dir.path.sep;
            const toolchain_versions_path = try std.fmt.allocPrint(allocator, "{s}{c}toolchain", .{ toolchain_path, sep });
            defer allocator.free(toolchain_versions_path);
            try std.Io.Dir.cwd().createDirPath(init.io, toolchain_versions_path);

            const toolchain_install_path = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ toolchain_versions_path, sep, version });
            defer allocator.free(toolchain_install_path);
            try std.Io.Dir.cwd().createDirPath(init.io, toolchain_install_path);

            const toolchain_bin_path = try std.fmt.allocPrint(allocator, "{s}{c}bin", .{ toolchain_install_path, sep });
            defer allocator.free(toolchain_bin_path);
            try std.Io.Dir.cwd().createDirPath(init.io, toolchain_bin_path);

            const flintc_bin_path = try std.fmt.allocPrint(allocator, "{s}{c}flintc", .{ toolchain_bin_path, sep });
            defer allocator.free(flintc_bin_path);

            const fls_bin_path = try std.fmt.allocPrint(allocator, "{s}{c}fls", .{ toolchain_bin_path, sep });
            defer allocator.free(fls_bin_path);

            try net.downloadFile(init.io, allocator, flintc.url, flintc_bin_path);
            try net.downloadFile(init.io, allocator, fls.url, fls_bin_path);

            if (builtin.os.tag != .windows) {
                const flintc_file = try std.Io.Dir.cwd().openFile(init.io, flintc_bin_path, .{});
                defer flintc_file.close(init.io);
                try flintc_file.setPermissions(init.io, .executable_file);

                const fls_file = try std.Io.Dir.cwd().openFile(init.io, fls_bin_path, .{});
                defer fls_file.close(init.io);
                try fls_file.setPermissions(init.io, .executable_file);
            }

            try State.addToolchainInstalled(init.io, allocator, toolchain_path, version);

            if (continuation) |next| {
                continuation = .install;
                continue :sw next;
            }
            return 0;
        },
        .update => {
            const old_newest: []const u8 = try allocator.dupe(u8, (try Registry.getNewestToolchainVersion(init.io, allocator, toolchain_path)));
            defer allocator.free(old_newest);
            try Registry.delete(init.io, allocator, toolchain_path);
            const new_newest = try Registry.getNewestToolchainVersion(init.io, allocator, toolchain_path);
            if (std.mem.eql(u8, old_newest, new_newest)) {
                std.log.info("No new Flint version available, newest version is still {s}", .{old_newest});
            } else {
                try stdout.print("New Flint version found: '{s}'. Do you want to execute 'flint upgrade' now? [y/N] ", .{new_newest});
                var out: [1]u8 = @splat(0);
                try stdin.readSliceAll(&out);
                switch (out[0]) {
                    'y', 'Y' => {},
                    'n', 'N', '\n' => return 0,
                    else => {
                        std.log.err("Expected one of 'y', 'Y', 'n' or 'N' but got '{c}'", .{out[0]});
                        return 1;
                    },
                }
                version = try Registry.getNewestToolchainVersion(init.io, allocator, toolchain_path);
                continue :sw .upgrade;
            }
            return 0;
        },
        .upgrade => {
            if (continuation) |prev| switch (prev) {
                .install => {
                    // Now that the newest version is installed, we can remove the currently active version
                    if (active) |curr| {
                        version = curr;
                        continuation = .upgrade;
                        continue :sw .remove;
                    } else {
                        continuation = null;
                        continue :sw .@"switch";
                    }
                },
                .remove => {
                    // Now that we have removed the previous version we can switch to the newest version it
                    version = try Registry.getNewestToolchainVersion(init.io, allocator, toolchain_path);
                    continuation = null;
                    continue :sw .@"switch";
                },
                else => @panic("Unrecognized continuation sequence"),
            } else {
                // First install newest version
                continuation = .upgrade;
                active =
                    if ((try State.get(init.io, allocator, toolchain_path)).toolchain_active) |a|
                        try allocator.dupe(u8, a)
                    else
                        null;
                try Registry.delete(init.io, allocator, toolchain_path);
                version = try Registry.getNewestToolchainVersion(init.io, allocator, toolchain_path);
                continue :sw .install;
            }
        },
        .remove => {
            try State.removeToolchainInstalled(init.io, allocator, toolchain_path, version);
            if (continuation) |next| {
                continuation = .remove;
                continue :sw next;
            }
            return 0;
        },
        .@"switch" => {
            try State.setActiveToolchain(init.io, allocator, toolchain_path, version);
            return 0;
        },
        .init => return init_cmd.main(init.io, allocator, iter),
        .fetch => return fetch_cmd.main(init.io, allocator, iter),
        .build => return build_cmd.main(init.io, allocator, iter),
    }
    unreachable;
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
        \\  You can use '-h' or '--help' on any subcommand to get additional information
        \\
        \\Available commands are:
        \\  help                Print this help message
        \\  fip                 Manage installations of Flint Interop Modules like 'fip-c'
        \\  target              Manage target toolchains installations
        \\    install
        \\    remove
        \\    list
        \\
        \\  list                List all available and installed versions of Flint
        \\  install [<version>] Install a specific version of Flint (just installs the newest Flint version if
        \\                      no version is provided)
        \\  update              Check for updates of Flint (force-fetches the 'registry.zon' file)
        \\  upgrade             Installs the newest Flint version and uninstalls the version currently in use
        \\  remove <version>    Remove a specific version of Flint
        \\  switch <version>    Use specific version of Flint
        \\
        \\  init                Initialize a new empty Flint project in the current working directory
        \\  fetch               Fetch all external dependencies described in the 'flint.toml' file
        \\  build               Build the Flint project from the information found in the '[build]' section of
        \\                      the 'flint.toml' file
        \\
    );
    try writer.flush();
}
