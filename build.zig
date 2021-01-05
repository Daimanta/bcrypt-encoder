const Builder = @import("std").build.Builder;
const version = @import("version.zig");
const builtin = @import("std").builtin;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("main", "main.zig");
    b.setPreferredReleaseMode(builtin.Mode.ReleaseSafe);
    _ = b.standardReleaseOptions();
    _ = b.version(version.major, version.minor, version.patch);
    b.default_step.dependOn(&exe.step);
}