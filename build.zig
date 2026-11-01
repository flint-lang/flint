const std = @import("std");

pub fn build(b: *std.Build) void {
    const git_exe_path: []const u8 = b.findProgram(.{ .names = &.{"git"} }) orelse
        @panic("'git' not found on this system");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap_dep = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    b.graph.poisonCache();
    const commit_hash: []const u8 = std.mem.trim(
        u8,
        b.run(&[_][]const u8{ git_exe_path, "rev-parse", "--short", "HEAD" }),
        &std.ascii.whitespace,
    );
    std.debug.print("-- Commit Hash is {s}\n", .{commit_hash});

    const commit_date: []const u8 = std.mem.trim(
        u8,
        b.run(&[_][]const u8{ git_exe_path, "log", "-1", "--date=format:%Y-%m-%d", "--format=%cd" }),
        &std.ascii.whitespace,
    );
    std.debug.print("-- Commit Date is {s}\n", .{commit_date});

    var defines = b.addOptions();
    defines.addOption([]const u8, "version", @import("build.zig.zon").version);
    defines.addOption([]const u8, "hash", commit_hash);
    defines.addOption([]const u8, "date", commit_date);

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
    run_cmd.addPassthruArgs();
}
