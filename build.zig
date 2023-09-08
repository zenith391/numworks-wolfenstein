const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    @setEvalBranchQuota(10000);
    const target = comptime std.zig.CrossTarget.parse(.{
        .arch_os_abi = "thumb-freestanding-eabihf",
        .cpu_features = "cortex_m7",
    }) catch unreachable;

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addObject(.{
        .name = "numworks-app-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addObjectFile(.{ .path = "icon.o" });
    exe.single_threaded = true;
    exe.strip = true;
    exe.stack_size = 32 * 1024; // about 8 KiB of stack sounds reasonable

    const zalgebra_dep = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });
    exe.addModule("zalgebra", zalgebra_dep.module("zalgebra"));

    const generateIcon = b.addSystemCommand(&.{ "nwlink", "png-icon-o", "icon.png", "icon.o" });
    exe.step.dependOn(&generateIcon.step);

    const install_exe = b.addInstallFile(exe.getOutputSource(), "numworks-app-zig.nwa");
    install_exe.step.dependOn(&exe.step);

    const run_cmd = b.addSystemCommand(&.{ "npx", "--yes", "--", "nwlink@0.0.16", "install-nwa", "zig-out/numworks-app-zig.nwa" });
    //const run_cmd = b.addSystemCommand(&.{ "nwlink", "install-nwa", "zig-out/numworks-app-zig.nwa" });
    run_cmd.step.dependOn(&install_exe.step);

    const run_step = b.step("run", "Upload and run the app (a NumWorks calculator must be connected)");
    run_step.dependOn(&run_cmd.step);
}
