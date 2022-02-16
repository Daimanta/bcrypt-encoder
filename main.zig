const std = @import("std");

const clap = @import("clap.zig");
const version = @import("version.zig");

const bcrypt = std.crypto.pwhash.bcrypt;
const bits = std.os;
const debug = std.debug;
const linux = std.os.linux;
const TCSA = bits.TCSA;
const windows = std.os.windows;

const Allocator = std.mem.Allocator;
var default_allocator = std.heap.page_allocator;

const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const HANDLE = std.os.windows.HANDLE;
const LPDWORD = *DWORD;
const WINAPI = std.os.windows.WINAPI;

const DEFAULT_ROUNDS: u6 = 10;
const Mode = enum { encrypt, check };

pub fn main() !void {
    var allocator = default_allocator;

    // First we specify what parameters our program can take.
    // We can use `parseParam` to parse a string to a `Param(Help)`
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("-c, --check <HASH>     Prompts for a password. 'true' or 'false' will be returned whether the password matches the hash. Cannot be combined with -er.") catch unreachable,
        clap.parseParam("-e, --encrypt     Prompts for a password. The result will be a bcrypt hash of the password. Cannot be combined with -c. Default option.") catch unreachable,
        clap.parseParam("-h, --help             Display this help and exit.") catch unreachable,
        clap.parseParam("-s, --stdin             Read the input text from stdin instead of prompting.") catch unreachable,
        clap.parseParam("-r, --rounds <NUM>     Indicates the log number of rounds, 1<= rounds <= 31. Default value is 10.") catch unreachable,
        clap.parseParam("-V, --version     Display the version number and exit.") catch unreachable,
    };

    // We then initialize an argument iterator. We will use the OsIterator as it nicely
    // wraps iterating over arguments the most efficient way on each os.
    var iter = try clap.args.OsIterator.init(allocator);
    defer iter.deinit();

    // Initalize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also just pass `null` to `parser.next` if you
    // don't care about the extra information `Diagnostics` provides.
    var diag = clap.Diagnostic{};

    var args = clap.parse(clap.Help, &params, .{ .diagnostic = &diag }) catch |err| {
        // Report 'Invalid argument [arg]'
        diag.report(std.io.getStdOut().writer(), err) catch {};
        return;
    };
    defer args.deinit();

    var rounds: ?u6 = null;
    var mode = Mode.encrypt;

    if (args.flag("--help")) {
        var buf: [1024]u8 = undefined;
        var slice_stream = std.io.fixedBufferStream(&buf);
        try clap.help(std.io.getStdOut().writer(), &params);
        print("Usage: bcrypt-encoder [OPTION] \n Hashes password with the bcrypt algorithm. Also allows checking if a password matches a provided hash.\n\n If arguments are possible, they are mandatory unless specified otherwise.\n", .{});
        print("{s}\n", .{slice_stream.getWritten()});
        return;
    } else if (args.flag("--version")) {
        print("Bcrypt-encoder version {d}.{d}.{d} © Léon van der Kaap 2021\nThis software is BSD 3-clause licensed.\n", .{ version.major, version.minor, version.patch });
        return;
    }
    if (args.option("--rounds")) |n| {
        var temp: u32 = 0;
        if (std.fmt.parseInt(u32, n[0..], 10)) |num| {
            temp = num;
        } else |_| {
            print("Round number is not a valid number\n", .{});
            return;
        }

        if (temp < 1 or temp > 31) {
            print("Rounds must be >=1 and <=31\n", .{});
            return;
        } else {
            rounds = @intCast(u6, temp);
        }
    }

    const encrypt = args.flag("-e");
    const use_stdin = args.flag("-s");
    var hash: [60]u8 = undefined;

    if (args.option("-c")) |n| {
        if (encrypt) {
            print("-c conflicts with -e\n", .{});
            return;
        }
        if (n.len != 60) {
            print("Invalid hash length. Expected length 60, got length {d}\n", .{n.len});
            return;
        }
        mode = Mode.check;
        for (n) |char, i| {
            hash[i] = char;
        }
    }

    var read_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer read_allocator.deinit();
    errdefer read_allocator.deinit();

    if (mode == Mode.encrypt) {
        var password: []u8 = undefined;
        if (use_stdin) {
            const stdin = std.io.getStdIn().reader();
            password = stdin.readAllAlloc(read_allocator.allocator(), 1 << 30) catch {
                print("Reading stdin failed\n", .{});
                return;
            };
        } else {
            password = read_string_silently(read_allocator.allocator()) catch |err| {
                const os = @import("builtin").os.tag;
                if (os == .windows) {
                    print("Error occurred while reading password. Exiting.\n", .{});
                } else if (os == .linux) {
                    if (err == error.NotATerminal) {
                        print("Input passed from stdin while not expecting it. Exiting.\n", .{});
                    } else {
                        print("Error occurred while reading password. Exiting.\n", .{});
                    }
                }
                return;
            };
        }
        const result = bcrypt_string(password[0..], rounds) catch |err| {
            print("Error: {s}\n", .{err});
            return;
        };
        print("{s}\n", .{result});
        zero_password(password);
        return;
    } else if (mode == Mode.check) {
        var password: []u8 = undefined;
        if (use_stdin) {
            const stdin = std.io.getStdIn().reader();
            password = stdin.readAllAlloc(read_allocator.allocator(), 1 << 30) catch {
                print("Reading stdin failed\n", .{});
                return;
            };
        } else {
            password = read_string_silently(read_allocator.allocator()) catch |err| {
                const os = @import("builtin").os.tag;
                if (os == .windows) {
                    print("Error occurred while reading password. Exiting.\n", .{});
                } else if (os == .linux) {
                    if (err == error.NotATerminal) {
                        print("Input passed from stdin while not expecting it. Exiting.\n", .{});
                    } else {
                        print("Error occurred while reading password. Exiting.\n", .{});
                    }
                }
                return;
            };
        }
        print("{s}\n", .{verify_password(hash, password[0..])});
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

fn bcrypt_string(password: []const u8, rounds: ?u6) std.crypto.pwhash.Error![]u8 {
    var params: bcrypt.Params = .{ .rounds_log = rounds orelse DEFAULT_ROUNDS };
    var hash_options: bcrypt.HashOptions = .{ .allocator = default_allocator, .params = params, .encoding = std.crypto.pwhash.Encoding.crypt };
    var buffer: [bcrypt.hash_length]u8 = undefined;
    _ = try bcrypt.strHash(password, hash_options, buffer[0..]);
    return default_allocator.dupe(u8, buffer[0..]);
}

fn verify_password(hash: [60]u8, password: []const u8) bool {
    bcrypt.strVerify(hash[0..], password, .{}) catch return false;
    return true;
}

pub extern "kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) callconv(WINAPI) BOOL;
pub extern "kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: LPDWORD) BOOL;

fn read_string_silently(allocator: std.mem.Allocator) ![]u8 {
    const os = @import("builtin").os.tag;

    var hidden_input: bool = false;
    if (os == .windows) {
        const ENABLE_ECHO_INPUT: u32 = 4;
        var handle = try windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE);
        var my_val: u32 = 0;
        var current_mode: LPDWORD = &my_val;
        _ = GetConsoleMode(handle, current_mode);
        _ = SetConsoleMode(handle, current_mode.* & ~ENABLE_ECHO_INPUT);
        hidden_input = true;
    } else if (os == .linux) {
        var import_termios = try bits.tcgetattr(bits.STDIN_FILENO);
        import_termios.lflag = import_termios.lflag & ~@as(u32, linux.ECHO);
        try bits.tcsetattr(bits.STDIN_FILENO, TCSA.NOW, import_termios);
        hidden_input = true;
    }
    if (hidden_input) {
        print("Please enter password:\n", .{});
    } else {
        print("Please enter password(Password will be visible!):\n", .{});
    }

    var newline: u8 = 13;
    if (os == .linux) newline = 10;

    const max_size: usize = 1000;
    // Deallocation at end of program

    const read = try std.io.getStdIn().reader().readUntilDelimiterAlloc(allocator, newline, max_size);

    if (os == .windows) {
        // Echo re-enables automatically
    } else if (os == .linux) {
        var import_termios = try bits.tcgetattr(bits.STDIN_FILENO);
        import_termios.lflag = import_termios.lflag | @as(u32, linux.ECHO);
        try bits.tcsetattr(bits.STDIN_FILENO, TCSA.NOW, import_termios);
    }
    return read;
}

pub fn print(comptime format_string: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(format_string, args) catch return;
}
