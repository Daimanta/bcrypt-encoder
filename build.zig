const std = @import("std");
const Builder = std.build.Builder;
const version = @import("version.zig");
const builtin = std.builtin;

pub fn build(b: *Builder) void {
    const current_zig_version = @import("builtin").zig_version;
    if (current_zig_version.major != 0 or current_zig_version.minor < 9) {
        std.debug.print("This project does not compile with a Zig version <0.9.x. Exiting.", .{});
        std.os.exit(1);
    }
    const exe = b.addExecutable("main", "main.zig");
    b.setPreferredReleaseMode(builtin.Mode.ReleaseSafe);
    _ = b.standardReleaseOptions();
    _ = b.version(version.major, version.minor, version.patch);
    b.default_step.dependOn(&exe.step);
    exe.install();
}
