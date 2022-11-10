const std = @import("std");
const InstallNativeArtifactStep = @import("InstallNativeArtifactStep.zig");
const FetchStep = @This();

step: std.build.Step,
b: *std.build.Builder,
ziget_native: *InstallNativeArtifactStep,
tar_native: *InstallNativeArtifactStep,
url: []const u8,
name: []const u8,
archive_path: []const u8,
extracted_path: []const u8,
archive_kind: ArchiveKind,

const ArchiveKind = enum {
        tar_gz,
};
const ParsedArchiveName = struct {
    name_len: usize,
    kind: ArchiveKind,
};
fn parseArchive(name: []const u8) ParsedArchiveName {
    {
        const tar_gz = ".tar.gz";
        if (std.mem.endsWith(u8, name, tar_gz))
            return .{ .name_len = name.len - tar_gz.len, .kind = .tar_gz };
    }
    {
        const tgz = ".tgz";
        if (std.mem.endsWith(u8, name, tgz))
            return .{ .name_len = name.len - tgz.len, .kind = .tar_gz };
    }
    std.debug.panic("TODO: unhandled archive extension '{s}'", .{name});
}

pub fn create(
    b: *std.build.Builder,
    ziget_native: *InstallNativeArtifactStep,
    tar_native: *InstallNativeArtifactStep,
    opt: struct {
        url: []const u8,
    },
) *FetchStep {
    var result = b.allocator.create(FetchStep) catch @panic("OutOfMemory");
    const basename = std.fs.path.basename(opt.url);
    const archive_info = parseArchive(basename);
    const archive_path = b.pathJoin(&.{ b.build_root, "download", basename });
    const name = basename[0 .. archive_info.name_len];
    result.* = FetchStep{
        .step = std.build.Step.init(.custom, b.fmt("fetch {s}", .{opt.url}), b.allocator, make),
        .b = b,
        .url = opt.url,
        .name = name,
        .ziget_native = ziget_native,
        .tar_native = tar_native,
        .archive_path = archive_path,
        .extracted_path = b.pathJoin(&.{ b.build_root, "dep", name }),
        .archive_kind = archive_info.kind,
    };

    // TODO: maybe it's overkill to have every single FetchStep depend
    //       on ziget_native/tar_native?
    result.step.dependOn(&ziget_native.step);
    result.step.dependOn(&tar_native.step);

    return result;
}

fn fetchArchive(self: FetchStep) !void {
    if (std.fs.accessAbsolute(self.archive_path, .{})) {
        return;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    }

    const download_dir = std.fs.path.dirname(self.archive_path).?;
    std.fs.cwd().makeDir(download_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };

    // TODO: lock file
    const tmp_path = self.b.fmt("{s}.downloading", .{self.archive_path});
    defer self.b.allocator.free(tmp_path);

    var args = std.ArrayList([]const u8).init(self.b.allocator);
    defer args.deinit();
    // TODO: should every single fetch call make like this?
    //try self.ziget_native.step.make();
    try args.append(self.ziget_native.installed_path);
    try args.append("--out");
    try args.append(tmp_path);
    try args.append(self.url);
    try run(self.b, args.items, .{});
    try std.os.rename(tmp_path, self.archive_path);
}

fn make(step: *std.build.Step) !void {
    const self = @fieldParentPtr(FetchStep, "step", step);

    if (std.fs.accessAbsolute(self.extracted_path, .{})) {
        return;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    }

    try self.fetchArchive();

    const dep_dir = std.fs.path.dirname(self.extracted_path).?;
    std.fs.cwd().makeDir(dep_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => |e| return e,
    };

    // TODO: lock file
    const tmp_path = self.b.fmt("{s}.extracting", .{self.extracted_path});
    defer self.b.allocator.free(tmp_path);

    try std.fs.cwd().deleteTree(self.extracted_path);
    try std.fs.cwd().deleteTree(tmp_path);
    try std.fs.cwd().makeDir(tmp_path);

    var args = std.ArrayList([]const u8).init(self.b.allocator);
    defer args.deinit();
    const use_system_tar = false;
    if (use_system_tar) {
        std.log.warn("using the system tar executable instead of our own", .{});
        try args.append("tar");
    } else {
        // TODO: should every single fetch call make like this?
        //try self.tar_native.step.make();
        try args.append(self.tar_native.installed_path);
    }
    try args.append("-xf");
    try args.append(self.archive_path);
    try run(self.b, args.items, .{
        .cwd = tmp_path,
    });

    // remove the single root subdirectory
    {
        const tmp_sub_path = self.b.pathJoin(&.{tmp_path, self.name});
        defer self.b.allocator.free(tmp_sub_path);
        {
            var sub_dir = try std.fs.cwd().openIterableDir(tmp_sub_path, .{});
            defer sub_dir.close();
            var it = sub_dir.iterate();
            while (try it.next()) |entry| {
                var src = self.b.pathJoin(&.{tmp_sub_path, entry.name});
                defer self.b.allocator.free(src);
                var dst = self.b.pathJoin(&.{tmp_path, entry.name});
                defer self.b.allocator.free(dst);
                try std.os.rename(src, dst);
            }
        }
        try std.fs.cwd().deleteDir(tmp_sub_path);
    }
    try std.os.rename(tmp_path, self.extracted_path);
}

fn run(builder: *std.build.Builder, argv: []const []const u8, opt: struct { cwd: ?[]const u8 = null }) !void {
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
    if (opt.cwd) |cwd| {
        child.cwd = cwd;
    } else {
        child.cwd = builder.build_root;
    }
    child.env_map = builder.env_map;

    try child.spawn();
    const result = try child.wait();
    switch (result) {
        .Exited => |code| if (code != 0) {
            std.log.err("{s} failed with exit code {}", .{std.fs.path.basename(argv[0]), code});
            std.os.exit(0xff);
        },
        else => {
            std.log.err("{s} failed with: {}", .{std.fs.path.basename(argv[0]), result});
            std.os.exit(0xff);
        },
    }
}
