const std = @import("std");
const bcrypt = std.crypto.pwhash.bcrypt;
const clap = @import("clap.zig");
const debug = std.debug;
const Allocator = std.mem.Allocator;

const DEFAULT_ROUNDS: u6 = 10;
const Mode = enum {
    encrypt, check
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // First we specify what parameters our program can take.
    // We can use `parseParam` to parse a string to a `Param(Help)`
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help             Display this help and exit.              ") catch unreachable,
        clap.parseParam("-r, --rounds <NUM>     Indicates the log number of rounds, 1<= rounds <= 31. Default value is 10.") catch unreachable,
        clap.parseParam("-c, --check <HASH>     Prompts for a password. 'true' or 'false' will be returned whether the password matches the hash. Cannot be combined with -er.") catch unreachable,
        clap.parseParam("-e, --encrypt     Prompts for a password. The result will be a bcrypt hash of the password. Cannot be combined with -c. Default option.") catch unreachable,
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = try clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Initalize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also just pass `null` to `parser.next` if you
    // don't care about the extra information `Diagnostics` provides.
    var diag: clap.Diagnostic = undefined;

    var args = clap.parseEx(clap.Help, &params, allocator, &iter, &diag) catch |err| {
        // Report 'Invalid argument [arg]'
        diag.report(std.io.getStdErr().outStream(), err) catch {};
        return;
    };
    defer args.deinit();

    var rounds: ?u6 = null;
    var mode = Mode.encrypt;

    if (args.flag("--help")) {
        var buf: [1024]u8 = undefined;
        var slice_stream = std.io.fixedBufferStream(&buf);
        try clap.help(slice_stream.outStream(), &params);
        debug.warn("Usage: bcrypt-encoder [OPTION] \n Hashes password with the bcrypt algorithm. Also allows checking if a password matches a provided hash.\n\n If arguments are possible, they are mandatory unless specified otherwise.\n", .{});
        debug.warn("{}\n", .{slice_stream.getWritten()});
        return;
    }
    if (args.option("--rounds")) |n| {
        var temp: u32 = 0;
        if (std.fmt.parseInt(u32, n[0..], 10)) |num| {
            temp = num;
        } else |err| {
            debug.warn("Round number is not a valid number\n", .{});
            return;
        }

        if (temp < 1 or temp > 31) {
            debug.warn("Rounds must be >=1 and <=31\n", .{});
            return;
        } else {
            rounds = @intCast(u6, temp);
        }
    }

    const encrypt = args.flag("-e");
    var hash: [60]u8 = undefined;

    if (args.option("-c")) |n| {
        if (encrypt) {
            debug.warn("-c conflicts with -e\n", .{});
            return;
        }
        if (n.len != 60) {
            debug.warn("Invalid hash length", .{});
            return;
        }
        mode = Mode.check;
        for (n) |char, i| {
            hash[i] = char;
        }
    }

    if (mode == Mode.encrypt) {
        var password: []u8 = try read_string_silently();
        try std.io.getStdOut().writer().print("{}\n", .{bcrypt_string(password[0..], rounds)});
        zero_password(password);
        return;
    } else if (mode == Mode.check) {
        var password = try read_string_silently();
        try std.io.getStdOut().writer().print("{}\n", .{verify_password(hash, password[0..])});
        zero_password(password);
        return;
    } else {
        unreachable;
    }
}

fn zero_password(password: []u8) void {
    for (password) |*char| {
        char.* = 0;
    }
}

fn bcrypt_string(password: []const u8, rounds: ?u6) ![60]u8 {
    return bcrypt.strHash(password, rounds orelse DEFAULT_ROUNDS);
}

fn verify_password(hash: [60]u8, password: []const u8) bool {
    bcrypt.strVerify(hash, password) catch |err| return false;
    return true;
}

fn read_string_silently() ![]u8 {
    const os = std.builtin.os.tag;

    var hidden_input: bool = false;
    if (os == .windows) {
        // TODO: Disable echo
    } else if (os == .linux) {
        const c = @cImport({
            @cInclude("stdlib.h");
        });
        _ = c.system("stty -echo");
        hidden_input = true;
    }
    if (hidden_input) {
        try std.io.getStdOut().writer().print("Please enter password:\n", .{});
    } else {
        try std.io.getStdOut().writer().print("Please enter password(Password will be visible!):\n", .{});
    }

    var newline: u8 = 13;
    if (os == .linux) newline = 10;

    const max_size: usize = 1000;
    // Deallocation at end of program
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    const read = try std.io.getStdIn().reader().readUntilDelimiterAlloc(&allocator.allocator, newline, max_size);

    if (os == .windows) {
        // TODO: Enable echo
    } else if (os == .linux) {
        const c = @cImport({
            @cInclude("stdlib.h");
        });
        _ = c.system("stty echo");
    }
    return read;
}
