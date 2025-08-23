const std = @import("std");

const clap2 = @import("clap2/clap2.zig");
const version = @import("version.zig");
const print_tools = @import("util/print_tools.zig");

const bcrypt = std.crypto.pwhash.bcrypt;
const bits = std.os;
const debug = std.debug;
const linux = std.os.linux;
const print = print_tools.print;
const TCSA = std.posix.TCSA;
const windows = std.os.windows;

const Allocator = std.mem.Allocator;
var default_allocator = std.heap.page_allocator;

const BOOL = std.os.windows.BOOL;
const DWORD = std.os.windows.DWORD;
const HANDLE = std.os.windows.HANDLE;
const LPDWORD = *DWORD;

const DEFAULT_ROUNDS: u6 = 10;
const Mode = enum { encrypt, check };

const help_message =
\\Usage: bcrypt-encoder [OPTION]
\\Hashes password with the bcrypt algorithm. Also allows checking if a password matches a provided hash.
\\If arguments are possible, they are mandatory unless specified otherwise.
\\
\\      -c, --check <HASH>      Prompts for a password. 'true' or 'false' will be returned whether the password matches the hash. Cannot be combined with -er.
\\      -e, --encrypt           Prompts for a password. The result will be a bcrypt hash of the password. Cannot be combined with -c. Default option.
\\      -h, --help              Display this help and exit.
\\      -s, --stdin             Read the input text from stdin instead of prompting.
\\      -r, --rounds <NUM>      Indicates the log number of rounds, 1<= rounds <= 31. Default value is 10.
\\      -V, --version           Display the version number and exit.
\\
\\
;
pub fn main() !void {
    const args: []const clap2.Argument = &[_]clap2.Argument{
        clap2.Argument.FlagArgument(null, &[_][]const u8{"help"}),
        clap2.Argument.FlagArgument("e", &[_][]const u8{"encrypt"}),
        clap2.Argument.FlagArgument("s", &[_][]const u8{"stdin"}),
        clap2.Argument.FlagArgument("V", &[_][]const u8{"version"}),
        clap2.Argument.OptionArgument("c", &[_][]const u8{"check"}, false),
        clap2.Argument.OptionArgument("r", &[_][]const u8{"rounds"}, false),
    };

    var parser = clap2.Parser.init(args, .{});
    defer parser.deinit();

    var rounds: ?u6 = null;
    var mode = Mode.encrypt;

    if (parser.flag("help")) {
        print(help_message, .{});
        std.posix.exit(0);
        return;
    } else if (parser.flag("V")) {
        print("Bcrypt-encoder version {d}.{d}.{d} © Léon van der Kaap 2021\nThis software is BSD 3-clause licensed.\n", .{ version.major, version.minor, version.patch });
        std.posix.exit(0);
        return;
    }
    if (parser.option("rounds").found) {
        const n = parser.option("rounds").value.?;
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
            rounds = @intCast(temp);
        }
    }

    const encrypt = parser.flag("e");
    const use_stdin = parser.flag("s");
    var hash: [60]u8 = undefined;

    if (parser.option("c").found) {
        const n = parser.option("c").value.?;
        if (encrypt) {
            print("-c conflicts with -e\n", .{});
            return;
        }
        if (n.len != 60) {
            print("Invalid hash length. Expected length 60, got length {d}\n", .{n.len});
            return;
        }
        mode = Mode.check;
        for (n, 0..) |char, i| {
            hash[i] = char;
        }
    }

    var read_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer read_allocator.deinit();
    errdefer read_allocator.deinit();

    if (mode == Mode.encrypt) {
        var password: []u8 = undefined;
        if (use_stdin) {
            const stdin = std.fs.File.stdin().deprecatedReader();
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
            print("Error: {}\n", .{err});
            return;
        };
        print("{s}\n", .{result});
        zero_password(password);
        return;
    } else if (mode == Mode.check) {
        var password: []u8 = undefined;
        if (use_stdin) {
            const stdin = std.fs.File.stdin().deprecatedReader();
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
        print("{}\n", .{verify_password(hash, password[0..])});
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
    const params: bcrypt.Params = .{ .rounds_log = rounds orelse DEFAULT_ROUNDS, .silently_truncate_password = false };
    const hash_options: bcrypt.HashOptions = .{ .allocator = default_allocator, .params = params, .encoding = std.crypto.pwhash.Encoding.crypt };
    var buffer: [bcrypt.hash_length]u8 = undefined;
    _ = try bcrypt.strHash(password, hash_options, buffer[0..]);
    return default_allocator.dupe(u8, buffer[0..]);
}

fn verify_password(hash: [60]u8, password: []const u8) bool {
    bcrypt.strVerify(hash[0..], password, .{.silently_truncate_password = false}) catch return false;
    return true;
}

pub extern "kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: LPDWORD) BOOL;

fn read_string_silently(allocator: std.mem.Allocator) ![]u8 {
    const os = @import("builtin").os.tag;

    var hidden_input: bool = false;
    if (os == .windows) {
        const ENABLE_ECHO_INPUT: u32 = 4;
        const handle = try windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE);
        var my_val: u32 = 0;
        const current_mode: LPDWORD = &my_val;
        _ = GetConsoleMode(handle, current_mode);
        _ = SetConsoleMode(handle, current_mode.* & ~ENABLE_ECHO_INPUT);
        hidden_input = true;
    } else if (os == .linux) {
        var import_termios = try std.posix.tcgetattr( std.posix.STDIN_FILENO);
        import_termios.lflag.ECHO = false;
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, TCSA.NOW, import_termios);
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

    const read = try std.fs.File.stdin().deprecatedReader().readUntilDelimiterAlloc(allocator, newline, max_size);

    if (os == .windows) {
        // Echo re-enables automatically
    } else if (os == .linux) {
        var import_termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
        import_termios.lflag.ECHO = true;
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, TCSA.NOW, import_termios);
    }
    return read;
}
