const std = @import("std");
const GitRepoStep = @This();

step: std.build.Step,
builder: *std.build.Builder,
url: []const u8,
name: []const u8,
branch: ?[]const u8 = null,
sha: ?[]const u8,
path: []const u8,

var cached_default_fetch_option: ?bool = null;
pub fn defaultFetchOption(b: *std.build.Builder) bool {
    if (cached_default_fetch_option) |_| {} else {
        cached_default_fetch_option = if (b.option(bool, "fetch", "automatically fetch network resources")) |o| o else false;
    }
    return cached_default_fetch_option.?;
}

pub fn create(b: *std.build.Builder, opt: struct {
    url: []const u8,
    branch: ?[]const u8 = null,
    sha: ?[]const u8,
    path: ?[]const u8 = null,
}) *GitRepoStep {
    var result = b.allocator.create(GitRepoStep) catch @panic("memory");
    const name = std.fs.path.basename(opt.url);
    result.* = GitRepoStep{
        .step = std.build.Step.init(.custom, "clone a git repository", b.allocator, make),
        .builder = b,
        .url = opt.url,
        .name = name,
        .branch = opt.branch,
        .sha = opt.sha,
        .path = if (opt.path) |p| (b.allocator.dupe(u8, p) catch @panic("memory")) else (std.fs.path.resolve(b.allocator, &[_][]const u8{
            b.build_root,
            "dep",
            name,
        })) catch @panic("memory"),
    };
    return result;
}

// TODO: this should be included in std.build, it helps find bugs in build files
fn hasDependency(step: *const std.build.Step, dep_candidate: *const std.build.Step) bool {
    for (step.dependencies.items) |dep| {
        // TODO: should probably use step.loop_flag to prevent infinite recursion
        //       when a circular reference is encountered, or maybe keep track of
        //       the steps encounterd with a hash set
        if (dep == dep_candidate or hasDependency(dep, dep_candidate))
            return true;
    }
    return false;
}

fn make(step: *std.build.Step) !void {
    const self = @fieldParentPtr(GitRepoStep, "step", step);

    std.fs.accessAbsolute(self.path, .{}) catch {
        {
            var args = std.ArrayList([]const u8).init(self.builder.allocator);
            defer args.deinit();
            try args.append("git");
            try args.append("clone");
            try args.append(self.url);
            // TODO: clone it to a temporary location in case of failure
            //       also, remove that temporary location before running
            try args.append(self.path);
            if (self.branch) |branch| {
                try args.append("-b");
                try args.append(branch);
            }
            try run(self.builder, args.items);
        }
        if (self.sha) |sha| {
            try run(self.builder, &[_][]const u8{
                "git",
                "-C",
                self.path,
                "checkout",
                sha,
                "-b",
                "fordep",
            });
        }
    };
}

fn run(builder: *std.build.Builder, argv: []const []const u8) !void {
    {
        var msg = std.ArrayList(u8).init(builder.allocator);
        defer msg.deinit();
        const writer = msg.writer();
        var prefix: []const u8 = "";
        for (argv) |arg| {
            try writer.print("{s}\"{s}\"", .{ prefix, arg });
            prefix = " ";
        }
        std.log.info("[RUN] {s}", .{msg.items});
    }

    var child = std.ChildProcess.init(argv, builder.allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.cwd = builder.build_root;
    child.env_map = builder.env_map;

    try child.spawn();
    const result = try child.wait();
    switch (result) {
        .Exited => |code| if (code != 0) {
            std.log.err("git clone failed with exit code {}", .{code});
            std.os.exit(0xff);
        },
        else => {
            std.log.err("git clone failed with: {}", .{result});
            std.os.exit(0xff);
        },
    }
}

// Get's the repository path and also verifies that the step requesting the path
// is dependent on this step.
pub fn getPath(self: *const GitRepoStep, who_wants_to_know: *const std.build.Step) []const u8 {
    if (!hasDependency(who_wants_to_know, &self.step))
        @panic("a step called GitRepoStep.getPath but has not added it as a dependency");
    return self.path;
}
