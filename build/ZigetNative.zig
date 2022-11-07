const Ziget = @This();

const std = @import("std");
const Pkg = std.build.Pkg;

exe: *std.build.LibExeObjStep,

pub fn create(b: *std.build.Builder) *Ziget {
    const exe = b.addExecutable("ziget-native", "ziget/ziget-cmdline.zig");
    exe.single_threaded = true;
    exe.addPackage(Pkg{
        .name = "ziget",
        .source = .{ .path = "ziget/ziget.zig" },
        .dependencies = &[_]Pkg {
            Pkg{
                .name = "ssl",
                .source = .{ .path = "ziget/iguana/ssl.zig" },
                .dependencies = &[_]Pkg {
                    Pkg{
                        .name = "iguana",
                        .source = .{ .path = "ziget/dep/iguanaTLS/src/main.zig" },
                    },
                },
            },
        },
    });
    const step = b.allocator.create(Ziget) catch unreachable;
    step.* = Ziget{ .exe = exe };
    b.step("ziget-native", "Build ziget-native").dependOn(&exe.step);
    return step;
}
