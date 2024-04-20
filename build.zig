const std = @import("std");
const Builder = std.Build;
const version = @import("version.zig");
const builtin = std.builtin;

pub fn build(b: *Builder) void {
    const current_zig_version = @import("builtin").zig_version;
    if (current_zig_version.major != 0 or current_zig_version.minor < 12) {
        std.debug.print("This project does not compile with a Zig version <0.12.x. Exiting.", .{});
        std.os.exit(1);
    }
    
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable(.{ .name = "bcrypt-encoder", .target = target, .root_source_file = .{ .path = "main.zig" }, .optimize = .ReleaseSafe, .version = .{ .major = version.major, .minor = version.minor, .patch = version.patch } });
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
