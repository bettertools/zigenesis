const std = @import("std");
const InstallNativeArtifactStep = @import("InstallNativeArtifactStep.zig");
const FetchStep = @import("FetchStep.zig");

pub fn add(
    b: *std.build.Builder,
    ziget_native: *InstallNativeArtifactStep,
    tar_native: *InstallNativeArtifactStep,
) *std.build.LibExeObjStep {
    const fetch = FetchStep.create(b, ziget_native, tar_native, .{
        .url = "https://www.python.org/ftp/python/3.9.13/Python-3.9.13.tgz",
    });
    const exe = b.addExecutable("python3", null);
    exe.step.dependOn(&fetch.step);
    var files = std.ArrayList([]const u8).init(b.allocator);
    // TODO: this is just a placeholder
    files.append(b.pathJoin(&.{ fetch.extracted_path, "src", "main.c" })) catch unreachable;
    exe.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8{
        "-std=c99",
    });
    exe.linkLibC();
    return exe;
}
