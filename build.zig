const std = @import("std");
const Builder = std.Build;
const version = @import("src/version.zig");
const builtin = std.builtin;

pub fn build(b: *Builder) void {
    const current_zig_version = @import("builtin").zig_version;
    if (current_zig_version.major != 0 or current_zig_version.minor < 15) {
        std.debug.print("This project does not compile with a Zig version <0.15.x. Exiting.", .{});
        std.os.exit(1);
    }
    
    const target = b.standardTargetOptions(.{});
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = .ReleaseSafe,
        .target = target
    });
    const exe = b.addExecutable(.{
        .name = "bcrypt-encoder",
        .root_module = module,
        .version = .{ .major = version.major, .minor = version.minor, .patch = version.patch } });
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
