const builtin = @import("builtin");
const std = @import("std");

pub fn cmdlineArgs() [][*:0]u8 {
    if (builtin.os.tag == .windows) {
        @panic("todo");
    }
    return std.os.argv.ptr[1 .. std.os.argv.len];
}
