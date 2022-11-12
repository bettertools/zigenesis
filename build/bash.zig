const std = @import("std");
const InstallNativeArtifactStep = @import("InstallNativeArtifactStep.zig");
const FetchStep = @import("FetchStep.zig");

const ConfigStep = struct {
    step: std.build.Step,
    b: *std.build.Builder,
    src: []const u8,
    pub fn create(b: *std.build.Builder, src: []const u8) *ConfigStep {
        const self = b.allocator.create(ConfigStep) catch unreachable;
        self.* = ConfigStep{
            .step = std.build.Step.init(.custom, "configure bash", b.allocator, make),
            .b = b,
            .src = src,
        };
        return self;
    }
    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(ConfigStep, "step", step);
        const files = &[_][]const u8 {
            "config.h",
            "pathnames.h",
            "version.h",
            "signames.h",
            "builtins/pipesize.h",
            "syntax.c",
        };
        for (files) |file| {
            var src = self.b.pathJoin(&.{self.b.build_root, "build", "bash", std.fs.path.basename(file)});
            defer self.b.allocator.free(src);
            var dst = self.b.pathJoin(&.{self.src, file});
            defer self.b.allocator.free(dst);
            try self.b.updateFile(src, dst);
        }
    }
};

pub const BashNative = struct {
    fetch: *FetchStep,
    exe: *std.build.LibExeObjStep,
};

pub fn add(
    b: *std.build.Builder,
    ziget_native: *InstallNativeArtifactStep,
    tar_native: *InstallNativeArtifactStep,
) BashNative {
    const fetch = FetchStep.create(b, ziget_native, tar_native, .{
        .url = "https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz",
    });
    const src = fetch.extracted_path;

    const config = ConfigStep.create(b, src);
    config.step.dependOn(&fetch.step);

    const include = b.pathJoin(&.{ src, "include" });
    const src_lib = b.pathJoin(&.{ src, "lib" });
    const builtins = b.pathJoin(&.{ src, "builtins" });

    const glob_lib = blk: {
        const lib = b.addStaticLibrary("glob", null);
        lib.step.dependOn(&config.step);
        const lib_src = b.pathJoin(&.{ src_lib, "glob" });
        var files = std.ArrayList([]const u8).init(b.allocator);
        for (&[_][]const u8 { "glob.c", "strmatch.c", "smatch.c", "xmbsrtowcs.c", "gmisc.c" }) |name| {
            files.append(b.pathJoin(&.{ lib_src, name })) catch unreachable;
        }
        lib.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
        lib.addIncludePath(lib_src);
        lib.addIncludePath(src);
        lib.addIncludePath(include);
        lib.addIncludePath(src_lib);
        lib.linkLibC();
        break :blk lib;
    };

    const malloc_lib = blk: {
        const lib = b.addStaticLibrary("malloc", null);
        lib.step.dependOn(&config.step);
        const lib_src = b.pathJoin(&.{ src_lib, "malloc" });
        var files = std.ArrayList([]const u8).init(b.allocator);
        for (&[_][]const u8 { "malloc.c", "trace.c", "stats.c", "table.c", "watch.c" }) |name| {
            files.append(b.pathJoin(&.{ lib_src, name })) catch unreachable;
        }
        lib.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-DRCHECK",
            "-Dbotch=programming_error",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
        lib.addIncludePath(lib_src);
        lib.addIncludePath(src);
        lib.addIncludePath(include);
        lib.addIncludePath(src_lib);
        lib.linkLibC();
        break :blk lib;
    };

    const tilde_lib = blk: {
        const lib = b.addStaticLibrary("tilde", null);
        lib.step.dependOn(&config.step);
        const lib_src = b.pathJoin(&.{ src_lib, "tilde" });
        var files = std.ArrayList([]const u8).init(b.allocator);
        for (&[_][]const u8 { "tilde.c" }) |name| {
            files.append(b.pathJoin(&.{ lib_src, name })) catch unreachable;
        }
        lib.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
        lib.addIncludePath(lib_src);
        lib.addIncludePath(src);
        lib.addIncludePath(include);
        lib.addIncludePath(src_lib);
        lib.linkLibC();
        break :blk lib;
    };

    const history_lib = blk: {
        const lib = b.addStaticLibrary("history", null);
        lib.step.dependOn(&config.step);
        const lib_src = b.pathJoin(&.{ src_lib, "readline" });
        var files = std.ArrayList([]const u8).init(b.allocator);
        const sources = &[_][]const u8 {
            "history.c", "histexpand.c", "histfile.c", "histsearch.c",// "shell.c",
            "savestring.c", "mbutil.c", //"xfree.c", "xmalloc.c",
        };
        for (sources) |name| {
            files.append(b.pathJoin(&.{ lib_src, name })) catch unreachable;
        }
        lib.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
        lib.addIncludePath(lib_src);
        lib.addIncludePath(src);
        lib.addIncludePath(include);
        lib.addIncludePath(src_lib);
        lib.linkLibC();
        break :blk lib;
    };

    const sh_lib = blk: {
        const lib = b.addStaticLibrary("sh", null);
        lib.step.dependOn(&config.step);
        const lib_src = b.pathJoin(&.{ src_lib, "sh" });
        var files = std.ArrayList([]const u8).init(b.allocator);
        for (lib_sh_src) |name| {
            files.append(b.pathJoin(&.{ lib_src, name })) catch unreachable;
        }
        lib.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
        lib.addIncludePath(lib_src);
        lib.addIncludePath(src);
        lib.addIncludePath(include);
        lib.addIncludePath(src_lib);
        lib.linkLibC();
        break :blk lib;
    };

    const readline_lib = blk: {
        const lib = b.addStaticLibrary("readline", null);
        lib.step.dependOn(&config.step);
        const lib_src = b.pathJoin(&.{ src_lib, "readline" });
        var files = std.ArrayList([]const u8).init(b.allocator);
        for (lib_readline_src) |name| {
            files.append(b.pathJoin(&.{ lib_src, name })) catch unreachable;
        }
        lib.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
        lib.addIncludePath(lib_src);
        lib.addIncludePath(src);
        lib.addIncludePath(include);
        lib.addIncludePath(src_lib);
        lib.linkLibC();
        break :blk lib;
    };

    const mkbuiltins = blk: {
        const exe = b.addExecutable("mkbuiltins", null);
        exe.addCSourceFiles(&[_][]const u8 {
            b.pathJoin(&.{ builtins, "mkbuiltins.c" }),
        }, &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
        });
        exe.addIncludePath(src);
        exe.addIncludePath(include);
        exe.addIncludePath(src_lib);
        exe.linkLibC();

        const step = b.allocator.create(std.build.Step) catch unreachable;
        step.* = std.build.Step.initNoOp(.custom, "mkbuiltin invocations", b.allocator);

        for (defs) |def| {
            const run = exe.run();
            run.cwd = builtins;
            run.addArg("-D");
            run.addArg(".");
            run.addArg(def);
            step.dependOn(&run.step);
        }

        {
            const run = exe.run();
            run.cwd = builtins;
            run.addArg("-externfile");
            run.addArg("builtext.h");
            //run.addArg("-includefile");
            //run.addArg("builtext.h");
            run.addArg("-structfile");
            run.addArg("builtins.c");
            run.addArg("-noproduction");
            run.addArg("-D");
            run.addArg(".");
            for (defs) |def| {
                run.addArg(def);
            }
            step.dependOn(&run.step);
        }
        break :blk step;
    };

    const builtins_lib = blk: {
        const lib = b.addStaticLibrary("builtins", null);
        lib.step.dependOn(mkbuiltins);
        const lib_src = b.pathJoin(&.{ builtins });
        var files = std.ArrayList([]const u8).init(b.allocator);
        for (lib_builtins_src) |name| {
            files.append(b.pathJoin(&.{ lib_src, name })) catch unreachable;
        }
        lib.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8 {
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
        lib.addIncludePath(lib_src);
        lib.addIncludePath(src);
        lib.addIncludePath(include);
        lib.addIncludePath(src_lib);
        lib.linkLibC();
        break :blk lib;
    };

    const exe = b.addExecutable("bash", null);
    {
        var files = std.ArrayList([]const u8).init(b.allocator);
        inline for (src_names) |name| {
            files.append(b.pathJoin(&.{ src, name ++ ".c" })) catch unreachable;
        }
        exe.addCSourceFiles(files.toOwnedSlice(), &[_][]const u8{
            "-std=c99",
            "-DHAVE_CONFIG_H",
            "-DSHELL",
            "-DRCHECK",
            "-DPROGRAM=\"bash\"",
            "-DLOCALEDIR=\"/usr/local/share/locale\"",
            "-DPACKAGE=\"bash\"",
            "-DCONF_HOSTTYPE=\"x86_64\"",
            "-DCONF_VENDOR=\"pc\"",
            "-DCONF_OSTYPE=\"linux-gnu\"",
            "-DCONF_MACHTYPE=\"x86_64-pc-linux-gnu\"",
            "-Dbotch=programming_error",
            "-Wno-parentheses",
            "-Wno-format-security",
        });
    }
    exe.addIncludePath(src);
    exe.addIncludePath(include);
    exe.addIncludePath(src_lib);

    exe.linkLibC();
    exe.linkLibrary(glob_lib);
    exe.linkLibrary(malloc_lib);
    exe.linkLibrary(tilde_lib);
    exe.linkLibrary(history_lib);
    exe.linkLibrary(sh_lib);
    exe.linkLibrary(readline_lib);
    exe.linkLibrary(builtins_lib);
    exe.linkSystemLibraryName("termcap");
    exe.linkSystemLibraryName("dl");

    return .{ .fetch = fetch, .exe = exe };
}

const src_names = &[_][]const u8 {
    "shell",
    "eval",
    "y.tab",
    "general",
    "make_cmd",
    "print_cmd",
    "dispose_cmd",
    "execute_cmd",
    "variables",
    "copy_cmd",
    "error",
    "expr",
    "flags",
    "jobs",
    "subst",
    "hashcmd",
    "hashlib",
    "mailcheck",
    "trap",
    "input",
    "unwind_prot",
    "pathexp",
    "sig",
    "test",
    "version",
    "alias",
    "array",
    "arrayfunc",
    "assoc",
    "braces",
    "bracecomp",
    "bashhist",
    "bashline",
    "list",
    "stringlib",
    "locale",
    "findcmd",
    "redir",
    "pcomplete",
    "pcomplib",
    "syntax",
    "xmalloc",
};

const defs = [_][]const u8 {
    "alias.def",
    "bind.def",
    "break.def",
    "builtin.def",
    "caller.def",
    "cd.def",
    "colon.def",
    "command.def",
    "declare.def",
    "echo.def",
    "enable.def",
    "eval.def",
    "exec.def",
    "exit.def",
    "fc.def",
    "fg_bg.def",
    "hash.def",
    "help.def",
    "history.def",
    "jobs.def",
    "kill.def",
    "let.def",
    "mapfile.def",
    "pushd.def",
    "read.def",
    "return.def",
    "set.def",
    "setattr.def",
    "shift.def",
    "source.def",
    "suspend.def",
    "test.def",
    "times.def",
    "trap.def",
    "type.def",
    "ulimit.def",
    "umask.def",
    "wait.def",
    "getopts.def",
    "shopt.def",
    "printf.def",
    "complete.def",
};

const lib_builtins_src = [_][]const u8 {
    "builtins.c",
    "alias.c",
    "bind.c",
    "break.c",
    "builtin.c",
    "caller.c",
    "cd.c",
    "colon.c",
    "command.c",
    "common.c",
    "declare.c",
    "echo.c",
    "enable.c",
    "eval.c",
    "evalfile.c",
    "evalstring.c",
    "exec.c",
    "exit.c",
    "fc.c",
    "fg_bg.c",
    "hash.c",
    "help.c",
    "history.c",
    "jobs.c",
    "kill.c",
    "let.c",
    "mapfile.c",
    "pushd.c",
    "read.c",
    "return.c",
    "set.c",
    "setattr.c",
    "shift.c",
    "source.c",
    "suspend.c",
    "test.c",
    "times.c",
    "trap.c",
    "type.c",
    "ulimit.c",
    "umask.c",
    "wait.c",
    "getopts.c",
    "shopt.c",
    "printf.c",
    "getopt.c",
    "bashgetopt.c",
    "complete.c",
};

const lib_sh_src = [_][]const u8 {
    "clktck.c",
    "clock.c",
    "getenv.c",
    "oslib.c",
    "setlinebuf.c",
    "strnlen.c",
    "itos.c",
    "zread.c",
    "zwrite.c",
    "shtty.c",
    "shmatch.c",
    "eaccess.c",
    "netconn.c",
    "netopen.c",
    "timeval.c",
    "makepath.c",
    "pathcanon.c",
    "pathphys.c",
    "tmpfile.c",
    "stringlist.c",
    "stringvec.c",
    "spell.c",
    "shquote.c",
    "strtrans.c",
    "snprintf.c",
    "mailstat.c",
    "fmtulong.c",
    "fmtullong.c",
    "fmtumax.c",
    "zcatfd.c",
    "zmapfd.c",
    "winsize.c",
    "wcsdup.c",
    "fpurge.c",
    "zgetline.c",
    "mbscmp.c",
    "uconvert.c",
    "ufuncs.c",
    "casemod.c",
    "input_avail.c",
    "mbscasecmp.c",
    "fnxform.c",
    "unicode.c",
    "shmbchar.c",
    "strvis.c",
    "utf8.c",
    "random.c",
    "gettimeofday.c",
    "timers.c",
    "wcsnwidth.c",
    "mbschr.c",
    "strtoimax.c",
};

const lib_readline_src = [_][]const u8 {
    "readline.c",
    "vi_mode.c",
    "funmap.c",
    "keymaps.c",
    "parens.c",
    "search.c",
    "rltty.c",
    "complete.c",
    "bind.c",
    "isearch.c",
    "display.c",
    "signals.c",
    "util.c",
    "kill.c",
    "undo.c",
    "macro.c",
    "input.c",
    "callback.c",
    "terminal.c",
    "text.c",
    "nls.c",
    "misc.c",
    "history.c",
    "histexpand.c",
    "histfile.c",
    "histsearch.c",
    //"shell.c",
    "savestring.c",
    "mbutil.c",
    "tilde.c",
    "colors.c",
    "parse-colors.c",
    //"xmalloc.c",
    //"xfree.c",
    "compat.c",
};
