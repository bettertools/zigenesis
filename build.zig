const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;
const Step = std.build.Step;
const Pkg = std.build.Pkg;

const GitRepoStep = @import("build/GitRepoStep.zig");
const ZigetNative = @import("build/ZigetNative.zig");
const lua = @import("build/lua.zig");

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const ziget_native = ZigetNative.create(b);

    {
        const update = UpdateZigetStep.create(b);
        b.step("update-ziget", "Update the ziget with master").dependOn(&update.step);
    }
    _ = lua.add(b, target, mode, ziget_native);
}

const UpdateZigetStep = struct {
    step: Step,
    b: *Builder,
    clone: *GitRepoStep,
    local_ziget_path: []const u8,
    run_zig_build: *std.build.RunStep,
    pub fn create(b: *Builder) *UpdateZigetStep {
        const step = b.allocator.create(UpdateZigetStep) catch unreachable;
        const local_ziget_path = b.pathJoin(&.{ b.build_root, "ziget" });
        const run_zig_build = b.addSystemCommand(&[_][]const u8 {
            b.zig_exe,
            "build",
            "iguana",
            "-Dfetch",
        });
        run_zig_build.cwd = local_ziget_path;
        step.* = .{
            .step = Step.init(.custom, "update-ziget", b.allocator, make),
            .b = b,
            .clone = GitRepoStep.create(b, .{
                .url = "https://github.com/marler8997/ziget",
                .branch = "master",
                .sha = null,
                .path = b.pathJoin(&.{ b.build_root, "ziget-tmp-for-update" }),
            }),
            .local_ziget_path = local_ziget_path,
            .run_zig_build = run_zig_build,
        };
        return step;
    }
    fn make(step: *Step) !void {
        const self = @fieldParentPtr(UpdateZigetStep, "step", step);
        try std.fs.cwd().deleteTree(self.clone.path);
        try self.clone.step.make();
        {
            const dot_git_filename = self.b.pathJoin(&.{ self.clone.path, ".git" });
            defer self.b.allocator.free(dot_git_filename);
            try std.fs.cwd().deleteTree(dot_git_filename);
        }
        {
            const git_ignore_filename = self.b.pathJoin(&.{ self.clone.path, ".gitignore" });
            defer self.b.allocator.free(git_ignore_filename);
            try std.fs.cwd().deleteFile(git_ignore_filename);
        }

        try std.fs.cwd().deleteTree(self.local_ziget_path);
        try std.fs.cwd().rename(self.clone.path, self.local_ziget_path);

        // run zig build -Dfetch to fetch the correct iguana repo
        try self.run_zig_build.step.make();

        // TODO: disable sha_check in ziget?

        const iguana = self.b.pathJoin(&.{ self.local_ziget_path, "dep", "iguanaTLS" });
        {
            const dot_git_filename = self.b.pathJoin(&.{ iguana, ".git" });
            defer self.b.allocator.free(dot_git_filename);
            try std.fs.cwd().deleteTree(self.b.pathJoin(&.{ iguana, ".git" }));
        }
    }
};

fn fileAppend(filename: []const u8, content: []const u8) !void {
    // NOTE: it looks like zig is missing a way to open a file without truncating it?
    var file = blk: {
        if (builtin.os.tag == .windows) {
            @panic("not impl");
        }

        break :blk std.fs.File {
            .handle = try std.os.open(
                filename,
                std.os.O.WRONLY | std.os.O.CLOEXEC | std.os.O.APPEND,
                0o666,
            ),
        };
    };
    defer file.close();
    try file.writer().writeAll(content);
}