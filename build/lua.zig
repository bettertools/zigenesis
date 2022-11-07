const std = @import("std");
const ZigetNative = @import("ZigetNative.zig");
const FetchStep = @import("FetchStep.zig");

pub fn add(
    b: *std.build.Builder,
    target: anytype,
    mode: anytype,
    ziget_native: *ZigetNative,
) *std.build.LibExeObjStep {
    const fetch = FetchStep.create(b, ziget_native, .{
        .url = "http://www.lua.org/ftp/lua-5.4.4.tar.gz",
    });
    const exe = b.addExecutable("lua", null);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.step.dependOn(&fetch.step);
    _ = b.addInstallArtifact(exe);
    var files = std.ArrayList([]const u8).init(b.allocator);
    files.append(b.pathJoin(&.{ fetch.extracted_path, "src", "lua.c" })) catch unreachable;
    inline for (core_objects) |obj| {
        files.append(b.pathJoin(&.{ fetch.extracted_path, "src", obj ++ ".c" })) catch unreachable;
    }
    inline for (aux_objects) |obj| {
        files.append(b.pathJoin(&.{ fetch.extracted_path, "src", obj ++ ".c" })) catch unreachable;
    }
    inline for (lib_objects) |obj| {
        files.append(b.pathJoin(&.{ fetch.extracted_path, "src", obj ++ ".c" })) catch unreachable;
    }

    exe.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8{
        "-std=c99",
    });
    exe.linkLibC();

    const step = b.step("lua", "build the LUA interpreter");
    step.dependOn(&exe.install_step.?.step);
    return exe;
}

const core_objects = [_][]const u8{
    "lapi", "lcode",   "lctype",   "ldebug",  "ldo",    "ldump",   "lfunc",  "lgc", "llex",
    "lmem", "lobject", "lopcodes", "lparser", "lstate", "lstring", "ltable", "ltm", "lundump",
    "lvm",  "lzio",
};
const aux_objects = [_][]const u8{"lauxlib"};
const lib_objects = [_][]const u8{
    "lbaselib", "ldblib",  "liolib",   "lmathlib", "loslib", "ltablib", "lstrlib",
    "lutf8lib", "loadlib", "lcorolib", "linit",
};
