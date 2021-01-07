const std = @import("std");
const Builder = std.build.Builder;
const version = @import("version.zig");
const builtin = std.builtin;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("main", "main.zig");
    const os = std.builtin.os.tag;
    if (os == .linux) {
        exe.linkSystemLibrary("c");
    }
    b.setPreferredReleaseMode(builtin.Mode.ReleaseSafe);
    _ = b.standardReleaseOptions();
    _ = b.version(version.major, version.minor, version.patch);
    b.default_step.dependOn(&exe.step);
    exe.install();
}
