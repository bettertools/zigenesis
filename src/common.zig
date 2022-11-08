const builtin = @import("builtin");
const std = @import("std");

pub fn oom(e: error{OutOfMemory}) noreturn {
    @panic(@tagName(e));
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.os.exit(0xff);
}

pub fn cmdlineArgs() [][*:0]u8 {
    if (builtin.os.tag == .windows) {
        @panic("todo");
    }
    return std.os.argv.ptr[1 .. std.os.argv.len];
}
