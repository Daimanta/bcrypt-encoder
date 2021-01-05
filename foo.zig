const std = @import("std");


pub fn main() !void {
    //var input: [1000]u8 = undefined;
    //try std.io.getStdOut().writer().print("{}\n", .{input});
    //const result = try std.io.getStdIn().reader().readUntilDelimiterOrEof(input[0..], '\n');
    //try std.io.getStdOut().writer().print("{}\n", .{result});
    const foo = "1234";
    const result = std.mem.readIntSliceForeign(u8, foo[0..]);
    try std.io.getStdOut().writer().print("{}\n", .{result});
}

test "foo" {
    try std.io.getStdOut().writer().print("{}\n", .{"foobar"[0..5]});
}