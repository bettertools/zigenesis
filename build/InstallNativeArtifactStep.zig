const std = @import("std");
const Builder = std.build.Builder;
const Step = std.build.Step;
const LibExeObjStep = std.build.LibExeObjStep;

step: Step,
artifact: *LibExeObjStep,
installed_path: []const u8,
do_pdb: bool,

const InstallNativeArtifactStep = @This();

pub fn create(artifact: *LibExeObjStep) *InstallNativeArtifactStep {

    if (artifact.kind != .exe) {
        @panic("non exe native artifact not implemented");
    }

    const b = artifact.builder;
    const self = b.allocator.create(InstallNativeArtifactStep) catch unreachable;
    self.* = InstallNativeArtifactStep{
        .step = Step.init(.custom, b.fmt("install native binary {s}", .{artifact.step.name}), b.allocator, make),
        .artifact = artifact,
        .installed_path = b.pathJoin(&.{ b.build_root, "native-out", self.artifact.out_filename }),
        .do_pdb = if (artifact.producesPdbFile()) blk: {
            if (artifact.kind == .exe or artifact.kind == .test_exe) {
                //break :blk InstallDir{ .bin = {} };
                break :blk true;
            } else {
                //break :blk InstallDir{ .lib = {} };
                break :blk true;
            }
        } else false,
    };
    // we call make inside our make instead I guess? Is this right?
    //self.step.dependOn(&artifact.step);
    return self;
}

fn make(step: *Step) !void {
    const self = @fieldParentPtr(InstallNativeArtifactStep, "step", step);

    // TODO: is this the right place to call this?
    try self.artifact.step.make();

    const b = self.artifact.builder;

    {
        const native_out_dir = std.fs.path.dirname(self.installed_path).?;
        std.fs.cwd().makeDir(native_out_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
    }

    try b.updateFile(self.artifact.getOutputSource().getPath(b), self.installed_path);
    if (self.artifact.isDynamicLibrary() and self.artifact.version != null and self.artifact.target.wantSharedLibSymLinks()) {
        @panic("not impl");
        //try doAtomicSymLinks(b.allocator, self.installed_path, self.artifact.major_only_filename.?, self.artifact.name_only_filename.?);
    }
    if (self.artifact.isDynamicLibrary() and self.artifact.target.isWindows() and self.artifact.emit_implib != .no_emit) {
        @panic("not impl");
        //const full_implib_path = b.getInstallPath(self.dest_dir, self.artifact.out_lib_filename);
        //try b.updateFile(self.artifact.getOutputLibSource().getPath(b), full_implib_path);
    }
    if (self.do_pdb) {
        @panic("not impl");
        //const full_pdb_path = b.getInstallPath(pdb_dir, self.artifact.out_pdb_filename);
        //try b.updateFile(self.artifact.getOutputPdbSource().getPath(b), full_pdb_path);
    }
}
