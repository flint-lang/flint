const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap_dep = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    const commit_hash: []const u8 = std.mem.trim(
        u8,
        b.run(&[_][]const u8{ "git", "rev-parse", "--short", "HEAD" }),
        &std.ascii.whitespace,
    );
    std.debug.print("-- Commit Hash is {s}\n", .{commit_hash});

    const build_date: []const u8 = blk: {
        const current_timestamp: u64 = @intCast(std.Io.Timestamp.now(b.graph.io, .real).toSeconds());
        const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = current_timestamp };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        break :blk b.fmt("{d}-{d:0>2}-{d:0>2}", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1, // day_index is 0-based
        });
    };
    std.debug.print("-- Build Date is {s}\n", .{build_date});

    var defines = b.addOptions();
    defines.addOption([]const u8, "version", @import("build.zig.zon").version);
    defines.addOption([]const u8, "hash", commit_hash);
    defines.addOption([]const u8, "date", build_date);

    const exe = b.addExecutable(.{
        .name = "flint",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "clap", .module = clap_dep.module("clap") },
                .{ .name = "defines", .module = defines.createModule() },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
