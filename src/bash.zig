/// Implementation of BASH
/// Docs: https://www.gnu.org/software/bash/manual/bash.html
const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");

const testing = std.testing;
const Allocator = std.mem.Allocator;

const oom = common.oom;
const fatal = common.fatal;

pub fn main() !u8 {
    var sw = struct {
        command: bool = false,
    }{ };

    const args = blk: {
        const all_args = common.cmdlineArgs();
        var non_option_len: usize = 0;
        for (all_args) |arg_ptr| {
            const arg = std.mem.span(arg_ptr);
            if (!std.mem.startsWith(u8, arg, "-")) {
                all_args[non_option_len] = arg;
                non_option_len += 1;
            } else if (!std.mem.startsWith(u8, arg, "--")) {
                if (arg.len == 1) {
                    fatal("unknown cmdline option '-'", .{});
                }
                for (arg[1..]) |c| {
                    switch (c) {
                        'c' => sw.command = true,
                        else => {
                            fatal("unknown cmdline switch '-{c}'", .{c});
                        },
                    }
                }
            } else {
                fatal("unknown cmdline option '{s}'", .{arg});
            }
        }
        break :blk all_args[0 .. non_option_len];
    };

    if (sw.command)
        fatal("-c option not implemented", .{});

    if (args.len == 0) {
        //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        //var read_buffer =
        var source = Source{ .stdin = .{} };
        return try execFile(&source);
    } else {
        const script_file = std.mem.span(args[0]);
        const script_args = args[1..];
        if (script_args.len > 0)
            fatal("todo: handle script arguments", .{});

        var arena = if (builtin.os.tag == .windows) std.heap.ArenaAllocator.init(std.heap.page_allocator) else {};
        var file = std.fs.cwd().openFileZ(script_file, .{}) catch |err| switch (err) {
            error.FileNotFound => fatal("{s}: No such file or directory", .{script_file}),
            else => |e| return e,
        };
        //defer file.close();
        const mem = blk: {
            // TODO: windows also supports a MemoryMap API, it might be faster than reading the file into memory
            if (builtin.os.tag == .windows)
                break :blk try file.readToEndAlloc(arena.allocator(), std.math.maxInt(usize));
            break :blk try std.os.mmap(
                null, try file.getEndPos(), std.os.PROT.READ,
                std.os.MAP.PRIVATE, file.handle, 0);
        };
        //defer if (builtin.os.tag == .windows) { } else std.os.munmap(mem);

        var source = Source{ .file = .{ .filename_for_error = script_file, .mem = mem } };
        return try execFile(&source);
    }
}

fn nextLine(reader: anytype, read_buf: *std.ArrayListUnmanaged(u8)) !?[]u8 {
    if (read_buf.items.len > 0)
        fatal("TODO: parse left-over...", .{});

    while (true) {
        const unused = blk: {
            const unused = read_buf.unusedCapacitySlice();
            if (unused.len == 0)
                read_buf.ensureUnusedCapacity(std.heap.page_allocator, std.mem.page_size) catch |e| oom(e);
            break :blk read_buf.unusedCapacitySlice();
        };

        const read = try reader.read(unused);
        if (read == 0) {
            if (read_buf.items.len == 0) return null;
            const line = read_buf.items;
            read_buf.items.len = 0;
            return line;
        }
        read_buf.items.len += read;
        const eol = findEndOfLine(read_buf.items) orelse continue;

        const line = read_buf.items[0 .. eol];
        const remaining = read_buf.items.len - eol - 1;
        std.mem.copy(
            u8,
            read_buf.items[0 .. remaining],
            read_buf.items[eol + 1..]
        );
        read_buf.items.len = remaining;
        return line;
    }
}

const Source = union(enum) {
    stdin: struct {
        read_buffer: std.ArrayListUnmanaged(u8) = .{},
    },
    file: File,
    const File = struct {
        filename_for_error: []const u8,
        mem: []const u8,
        read_offset: usize = 0,
        pub fn memTo(self: File, loc: [*]const u8) []const u8 {
            return self.mem[0 .. @ptrToInt(loc) - @ptrToInt(self.mem.ptr)];
        }
    };

    pub fn nextLineSource(self: *Source) !?[]const u8 {
        switch (self.*) {
            .stdin => |*stdin|
                return nextLine(std.io.getStdIn().reader(), &stdin.read_buffer),
            .file => |*file| {
                if (file.read_offset == file.mem.len)
                    return null;
                const rest = file.mem[file.read_offset..];
                const old = file.read_offset;
                const eol = findEndOfLine(rest) orelse {
                    file.read_offset = file.mem.len;
                    return file.mem[old..];
                };
                file.read_offset += eol + 1;
                return file.mem[old..file.read_offset-1];
            },
        }
    }
    pub fn format(
        self: Source,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .stdin => try writer.writeAll("bash"),
            .file => |*file| try writer.writeAll(file.filename_for_error),
        }
    }
};

fn findEndOfLine(text: []const u8) ?usize {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\n') {
            if (i == 0 or text[i-1] != '\\') {
                return i;
            }
        }
    }
    return null;
}

fn LimitSlice(comptime T: type) type {
    return struct {
        pub const Mut = struct {
            ptr: [*]T,
            limit: [*]T,
        };
        pub const Const = struct {
            ptr: [*]const T,
            limit: [*]const T,
            pub fn init(ptr: [*]const T, limit: [*]const T) Const {
                return .{ .ptr = ptr, .limit = limit };
            }
            pub fn initSlice(s: []const T) Const {
                return .{ .ptr = s.ptr, .limit = s.ptr + s.len };
            }
            pub fn slice(self: Const) []const T {
                return self.ptr[0 .. @ptrToInt(self.limit) - @ptrToInt(self.ptr)];
            }
        };
    };
}

fn isFieldSep(ifs: []const u8, c: u8) bool {
    for (ifs) |sep| {
        if (c == sep)
            return true;
    }
    return false;
}

fn processLine(
    allocator: Allocator,
    words: *std.ArrayListUnmanaged([]const u8),
    ifs: []const u8,
    line: LimitSlice(u8).Const,
) error{OutOfMemory}!void {
    var next = line.ptr;

    while (true) {
        while (true) : (next += 1) {
            if (next == line.limit or next[0] == '#') return;
            if (!isFieldSep(ifs, next[0])) break;
        }

        if (next[0] == '$') {
            next = try expandDollarExpr(allocator, words, ifs, LimitSlice(u8).Const.init(next, line.limit));
        } else {
            const start = next;
            while (true) {
                next += 1;
                if (next == line.limit or isFieldSep(ifs, next[0])) break;
            }
            try words.append(allocator, start[0 .. @ptrToInt(next) - @ptrToInt(start)]);
        }
    }
}

// Shell Read/Execute Sequence:
// 1. Read input
// 2. Break input into words/operators, obey the quoting rules.  Alias
//    expansion is performed during this step.
// 3. Parse tokens into simple compound commands.
// 4. Perform expansions.  Tokens expanded into lists of filenames and command arguments.
// 5. Perform redirections.
// 6. Execute the command.
// 7. Optionally wait for command to complete and collect its exit status.


// 1. Brace Expansion
// 2. Tilde Expansion
// 3. Shell Parameter Expansion
// 4. Command Substitution
// 5. Arithemtic Expansion
// 6. Process Substitution
// 7. Word Splitting
// 8. Filename Expansion
// 9. Quote Removal


//3.5.3 Shell Parameter Expansion
fn expandDollarExpr(
    allocator: Allocator,
    words: *std.ArrayListUnmanaged([]const u8),
    ifs: []const u8,
    expr: LimitSlice(u8).Const,
) error{OutOfMemory}![*]const u8 {
    _ = ifs;
    var next = expr.ptr + 1;
    if (next == expr.limit) {
        try words.append(allocator, expr.slice());
        return expr.limit;
    }
    if (next[0] == '{') {
        std.debug.panic("TODO: perform brace expanseion '{s}'", .{expr.slice()});
    }
    std.debug.panic("TODO: process dollar expression '{s}'", .{expr.slice()});
}


fn processWord(
    allocator: Allocator,
    words: *std.ArrayListUnmanaged([]const u8),
    ifs: []const u8,
    word: []const u8,
) error{OutOfMemory}!void {
    _ = ifs;
    if (std.mem.startsWith(u8, word, "$")) {
        if (word.len == 0) {
            try words.append(allocator, word);
            return;
        }

    }
    try words.append(allocator, word);
}

const default_ifs = " \t\n";

const ScriptState = struct {
    ifs: []const u8,
};

fn countChars(src: []const u8, needle: u8) u32 {
    var count: u32 = 0;
    for (src) |c| {
        if (c == needle) {
            count += 1;
        }
    }
    return count;
}

fn execFile(source: *Source) !u8 {
    //var ifs: []const u8 = default_ifs;

    switch (source.*) {
        .stdin => @panic("not impl"),
        .file => |*file| {
            var it = Lexer{
                .ptr = file.mem.ptr,
                .limit = file.mem.ptr + file.mem.len,
            };
            var inside_command = false;
            while (it.next() catch |err| switch (err) {
                error.UnclosedSingleQuote, error.UnclosedDoubleQuote, error.UnclosedTickQuote, error.UnclosedParen => |e| {
                    const line_number = 1 + countChars(file.memTo(it.ptr), '\n');
                    const c_str = [1]u8 { getUnclosedChar(e) };
                    std.log.err("{s}: line {}: unexpected EOF while looking for matching `{s}`", .{source, line_number, c_str});
                    return 1;
                },
            }) |token| {
                switch (token) {
                    .eol => {
                        //std.log.info("  eol", .{});
                        inside_command = false;
                    },
                    .op => |op| {
                        std.log.info("  op {s}", .{@tagName(op)});
                        inside_command = true;
                    },
                    .word => |word| {
                        if (!inside_command) {
                            try std.io.getStdErr().writer().writeAll("execute command (type=4)...\n");
                        }
                        try std.io.getStdErr().writer().print("  0x0: '{s}'\n", .{word});
                        inside_command = true;
                        //std.log.info("  word '{s}'", .{word}),
                    },
                }
            }
            return 0;
        },
    }
//    while (true) {
//        const line = (try source.nextLineSource()) orelse {
//            return 0;
//        };
//
//        std.log.info("got line '{s}'", .{line});
//        var it = Lexer{ .ptr = line.ptr, .limit = line.ptr + line.len };
//        while (it.next() catch |err| switch (err) {
//            error.UnclosedSingleQuote => {
//                // TODO: use actual line number
//                const line_number: u32 = 0;
//                std.log.err("{s}: line {}: unexpected EOF while looking for matching `'`", .{source, line_number});
//                return 1;
//            },
//        }) |token| {
//            switch (token) {
//                .op => |op| std.log.info("  op {s} '{s}'", .{@tagName(op), op.str()}),
//                .word => |word| std.log.info("  word '{s}'", .{word}),
//            }
//        }

//        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//        defer arena.deinit();
//        var words = std.ArrayListUnmanaged([]const u8){ };
//        defer words.deinit(arena.allocator());
//        processLine(arena.allocator(), &words, ifs, LimitSlice(u8).Const.initSlice(line)) catch |e| oom(e);
//        if (words.items.len == 0) continue;
//
//        const cmd = words.items[0];
//        const args = words.items[1..];
//        if (builtin_map.get(cmd)) |b| {
//            std.log.info("TODO: execute builtin '{s}' with args:", .{@tagName(b)});
//            for (args) |arg, i| {
//                std.log.info("  [{}] '{s}'", .{i, arg});
//            }
//        } else {
//            std.log.info("TODO: execute external command '{s}'", .{cmd});
//            for (args) |arg, i| {
//                std.log.info("  [{}] '{s}'", .{i, arg});
//            }
//        }
//    }
}

const Builtin = enum {
    colon,
    period,
    @"export",
    echo,
};
const builtin_map = std.ComptimeStringMap(Builtin, .{
    .{ ":", .colon },
    .{ ".", .period },
    .{ "export", .@"export" },
    .{ "echo", .echo },
});

// words and operators
// words:
//     don't include unquoted metacharacters
// operators:
//     control or redirection operator
//     contain at least 1 unquoted metacharacter
// control operators:
//     |   ||   |&
//     &   &&
//     ;   ;&   ;;   ;;&
//     (   )
// redirection operators:
//     &>   &>>
//     >   >|   >&   >>
//     < <<   <&   <>   <<-   <<<
const Metachar = enum {
    space,
    tab,
    newline,
    vert_bar,
    ampersand,
    semicolon,
    lparen,
    rparen,
    lsquarebracket,
    rsquarebracket,
    pub fn maybe(c: u8) ?Metachar {
        return switch (c) {
            ' ' => return .space,
            '\t' => return .tab,
            '\n' => return .newline,
            '|' => return .vert_bar,
            '&' => return .ampersand,
            ';' => return .semicolon,
            '(' => return .lparen,
            ')' => return .rparen,
            '<' => return .lsquarebracket,
            '>' => return .rsquarebracket,
            else => return null,
        };
    }
};

const HeredocOp = enum {
    heredoc,
    heredoc_strip,
    heredoc_variant,
};
const NonHeredocOp = enum {
    pipe,
    pipe_both,
    @"or",
    @"async",
    @"and",
    end_cmd,
    case_break,
    case_cont,
    case_cont_if,
    lparen,
    rparen,
    redirect,
    redirect_force_clobber,
    redirect_fd,
    redirect_inout,
    redirect_append,
    redirect_both,
    redirect_both_append,
    redirect_in,
    redirect_in_fd,
};

const Op = enum {
    pipe,
    pipe_both,
    @"or",
    @"async",
    @"and",
    end_cmd,
    case_break,
    case_cont,
    case_cont_if,
    lparen,
    rparen,
    redirect,
    redirect_force_clobber,
    redirect_fd,
    redirect_inout,
    redirect_append,
    redirect_both,
    redirect_both_append,
    redirect_in,
    redirect_in_fd,
    heredoc,
    heredoc_strip,
    heredoc_variant,

    pub fn maybe(ptr: [*]const u8, limit: [*]const u8) ?Op {
        std.debug.assert(@ptrToInt(ptr) < @ptrToInt(limit));
        switch (ptr[0]) {
            '|' => return switch (if (ptr + 1 == limit) return .pipe else ptr[1]) {
                '|' => .@"or",
                '&' => .pipe_both,
                else => .pipe,
            },
            '&' => return switch (if (ptr + 1 == limit) return .@"async" else ptr[1]) {
                '&' => .@"and",
                '>' => return switch (if (ptr + 2 == limit) return .redirect_both else ptr[2]) {
                    '>' => .redirect_both_append,
                    else => .redirect_both,
                },
                else => .@"async",
            },
            ';' => return switch (if (ptr + 1 == limit) return .end_cmd else ptr[1]) {
                '&' => .case_cont,
                ';' => return switch (if (ptr + 2 == limit) return .case_break else ptr[2]) {
                    '&' => .case_cont_if,
                    else => .case_break,
                },
                else => .end_cmd,
            },
            '>' => return switch (if (ptr + 1 == limit) return .redirect else ptr[1]) {
                '|' => .redirect_force_clobber,
                '&' => .redirect_fd,
                '>' => .redirect_append,
                else => .redirect,
            },
            '<' => return switch (if (ptr + 1 == limit) return .redirect_in else ptr[1]) {
                '&' => .redirect_in_fd,
                '>' => .redirect_inout,
                '<' => return switch (if (ptr + 2 == limit) return .heredoc else ptr[2]) {
                    '-' => .heredoc_strip,
                    '<' => .heredoc_variant,
                    else => .heredoc,
                },
                else => .redirect_in,
            },
            '(' => return .lparen,
            ')' => return .rparen,
            else => return null,
        }
    }
    pub fn str(self: Op) []const u8 {
        return switch (self) {
            .pipe => "|",
            .pipe_both => "|&",
            .@"or" => "||",
            .@"async" => "&",
            .@"and" => "&&",
            .end_cmd => ";",
            .case_break => ";;",
            .case_cont => ";&",
            .case_cont_if => ";;&",
            .lparen => "(",
            .rparen => ")",
            .redirect => ">",
            .redirect_force_clobber => ">|",
            .redirect_fd => ">&",
            .redirect_inout => "<>",
            .redirect_append => ">>",
            .redirect_both => "&>",
            .redirect_both_append => "&>>",
            .redirect_in => "<",
            .redirect_in_fd => "<&",
            .heredoc => "<<",
            .heredoc_strip => "<<-",
            .heredoc_variant => "<<<",
        };
    }
    pub fn len(self: Op) u2 {
        return @intCast(u2, self.str().len);
    }
    pub fn heredocKind(self: Op) union(enum) {
        non_heredoc: NonHeredocOp,
        heredoc: HeredocOp,
    } {
        return switch (self) {
            .pipe => .{ .non_heredoc = .pipe },
            .pipe_both => .{ .non_heredoc = .pipe_both },
            .@"or" => .{ .non_heredoc = .@"or" },
            .@"async" => .{ .non_heredoc = .@"async" },
            .@"and" => .{ .non_heredoc = .@"and" },
            .end_cmd => .{ .non_heredoc = .end_cmd },
            .case_break => .{ .non_heredoc = .case_break },
            .case_cont => .{ .non_heredoc = .case_cont },
            .case_cont_if => .{ .non_heredoc = .case_cont_if },
            .lparen => .{ .non_heredoc = .lparen },
            .rparen => .{ .non_heredoc = .rparen },
            .redirect => .{ .non_heredoc = .redirect },
            .redirect_force_clobber => .{ .non_heredoc = .redirect_force_clobber },
            .redirect_fd => .{ .non_heredoc = .redirect_fd },
            .redirect_inout => .{ .non_heredoc = .redirect_inout },
            .redirect_append => .{ .non_heredoc = .redirect_append },
            .redirect_both => .{ .non_heredoc = .redirect_both },
            .redirect_both_append => .{ .non_heredoc = .redirect_both_append },
            .redirect_in => .{ .non_heredoc = .redirect_in },
            .redirect_in_fd => .{ .non_heredoc = .redirect_in_fd },
            .heredoc => .{ .heredoc = .heredoc },
            .heredoc_strip => .{ .heredoc = .heredoc_strip },
            .heredoc_variant => .{ .heredoc = .heredoc_variant },
        };
    }
};

//
//#define CMD_WANT_SUBSHELL  0x01	/* User wants a subshell: ( command ) */
//#define CMD_FORCE_SUBSHELL 0x02	/* Shell needs to force a subshell. */
//#define CMD_INVERT_RETURN  0x04	/* Invert the exit value. */
//#define CMD_IGNORE_RETURN  0x08	/* Ignore the exit value.  For set -e. */
//#define CMD_NO_FUNCTIONS   0x10 /* Ignore functions during command lookup. */
//#define CMD_INHIBIT_EXPANSION 0x20 /* Do not expand the command words. */
//#define CMD_NO_FORK	   0x40	/* Don't fork; just call execve */
//#define CMD_TIME_PIPELINE  0x80 /* Time a pipeline */
//#define CMD_TIME_POSIX	   0x100 /* time -p; use POSIX.2 time output spec. */
//#define CMD_AMPERSAND	   0x200 /* command & */
//#define CMD_STDIN_REDIR	   0x400 /* async command needs implicit </dev/null */
//#define CMD_COMMAND_BUILTIN 0x0800 /* command executed by `command' builtin */
//#define CMD_COPROC_SUBSHELL 0x1000
//#define CMD_LASTPIPE	    0x2000
//#define CMD_STDPATH	    0x4000	/* use standard path for command lookup */
//#define CMD_TRY_OPTIMIZING  0x8000	/* try to optimize this simple command */
//
const Command = struct {
    base: struct {
        line: u32,
    },
};

// Types of commands:
// simple
//   int flags;			/* See description of CMD flags. */
//   int line;			/* line number the command starts on */
//   WORD_LIST *words;		/* The program name, the arguments,
//              		   variable assignments, etc. */
//  REDIRECT *redirects;		/* Redirections to perform. */

// subshell
// coproc
// connection? 2 commands connected together (i.e. cmd1; cmd2
// for, case, while, if, connection?
// function_def, group
// select (optional)
// arithmetic (optional)
// conditional (optional)
// arithmetic_for (optional)
//enum command_type { cm_for, cm_case, cm_while, cm_if, cm_simple, cm_select,
//		    cm_connection, cm_function_def, cm_until, cm_group,
//		    cm_arith, cm_cond, cm_arith_for, cm_subshell, cm_coproc };

test "parse ops" {
    inline for (@typeInfo(Op).Enum.fields) |field| {
        const val = @intToEnum(Op, field.value);
        const str = val.str();
        try std.testing.expectEqual(@intCast(u2, str.len), val.len());
        try std.testing.expectEqual(val, Op.maybe(str.ptr, str.ptr + str.len).?);
    }
}

const LexStateStack = struct {
    const State = union(enum) {
        single_quoting: [*]const u8,
        double_quoting: [*]const u8,
        tick_quoting: [*]const u8,
        paren: [*]const u8,
    };

    // TODO: remove this hardcoded limitation
    arr: [100]State = undefined,
    idx: usize = 0,
    pub fn pop(self: *LexStateStack) void {
        std.debug.assert(self.idx > 0);
        self.idx -= 1;
    }
    pub fn peek(self: LexStateStack) ?State {
        return if (self.idx == 0) null else self.arr[self.idx - 1];
    }
    pub fn push(self: *LexStateStack, state: State) void {
        if (self.idx + 1 == self.arr.len) {
            @panic("too many state contexts");
        }
        self.arr[self.idx] = state;
        self.idx += 1;
    }
};

const UnclosedError = error {
    UnclosedSingleQuote,
    UnclosedDoubleQuote,
    UnclosedTickQuote,
    UnclosedParen,
};
pub fn getUnclosedChar(err: UnclosedError) u8 {
    return switch (err) {
        error.UnclosedSingleQuote => '\'',
        error.UnclosedDoubleQuote => '"',
        error.UnclosedTickQuote => '`',
        error.UnclosedParen => ')',
    };
}

const LexError = UnclosedError;

const Token = union(enum) {
    eol: void,
    op: NonHeredocOp,
    word: []const u8,
};
const Lexer = struct {
    ptr: [*]const u8,
    limit: [*]const u8,
    pub fn next(self: *Lexer) LexError!?Token {
        while (true) : (self.ptr += 1) {
            if (self.ptr == self.limit) return null;
            if (self.ptr[0] == ' ' or self.ptr[0] == '\t') continue;
            if (self.ptr[0] == '\n') {
                self.ptr += 1;
                return .eol;
            }
            break;
        }

        if (Op.maybe(self.ptr, self.limit)) |op| {
            self.ptr += op.len();
            switch (op.heredocKind()) {
                .non_heredoc => |op2| return .{ .op = op2 },
                .heredoc => |op2| return try self.scanHeredoc(op2),
            }
        }
        // since we're not at whitespace or op, we must be at a word I think?
        if (Metachar.maybe(self.ptr[0])) |m| {
            std.log.info("c '{}' meta is {s}", .{self.ptr[0], @tagName(m)});
        }
        std.debug.assert(Metachar.maybe(self.ptr[0]) == null);
        if (self.ptr[0] == '#') {
            while (true) {
                self.ptr += 1;
                if (self.ptr == self.limit) break;
                if (self.ptr[0] == '\n') {
                    self.ptr += 1;
                    break;
                }
            }
            return .eol;
        }

        var state_stack = LexStateStack{ };

        const start = self.ptr;
        if (start[0] == '\'') {
            state_stack.push(.{ .single_quoting = start });
        } else if (start[0] == '"') {
            state_stack.push(.{ .double_quoting = start });
        } else if (start[0] == '`') {
            state_stack.push(.{ .tick_quoting = start });
        }// don't need to check if it's '(' because that would have been caught in the Op.maybe

        //std.log.info("start word: '{s}'", .{start[0 .. 4]});
        while (true) {
            self.ptr += 1;
            const log = false;
            if (log and self.ptr != self.limit) {
                if (state_stack.peek()) |state| {
                    std.log.info("char '{}' state={}", .{std.zig.fmtEscapes(self.ptr[0..1]), state});
                } else {
                    std.log.info("char '{}' nostate", .{std.zig.fmtEscapes(self.ptr[0..1])});
                }
            }
            switch (state_stack.peek() orelse {
                const word_done = blk: {
                    if (self.ptr == self.limit)
                        break :blk true;
                    switch (self.ptr[0]) {
                        // metacharacters
                        ' ' => break :blk true,
                        '\t' => break :blk true,
                        '\n' => break :blk true,
                        '|' => break :blk true,
                        '&' => break :blk true,
                        ';' => break :blk true,
                        '(' => {
                            state_stack.push(.{ .paren = self.ptr });
                            break :blk false;
                        },
                        ')' => {
                            std.debug.panic("TODO: I think a random ')' is a syntax error", .{});
                        },
                        '<' => break :blk true, // TODO: is this right?
                        '>' => break :blk true, // TODO: is this right?

                        //
                        '\\' => {
                            @panic("todo: handle escape characters");
                        },
                        '\'' => {
                            state_stack.push(.{ .single_quoting = self.ptr });
                            break :blk false;
                        },
                        '"' => {
                            state_stack.push(.{ .double_quoting = self.ptr });
                            break :blk false;
                        },
                        '`' => {
                            state_stack.push(.{ .tick_quoting = self.ptr });
                            break :blk false;
                        },
                        else => break :blk false,
                    }
                };
                if (word_done)
                    return .{ .word = start[0 .. @ptrToInt(self.ptr) - @ptrToInt(start)] };
                continue;
            }) {
                .single_quoting => |start_quote| {
                    if (self.ptr == self.limit) {
                        self.ptr = start_quote;
                        return error.UnclosedSingleQuote;
                    }
                    // TODO: the escape check isn't right
                    if (self.ptr[0] == '\'' and (self.ptr-1)[0] != '\\') {
                        state_stack.pop();
                    }
                },
                .double_quoting => |start_quote| {
                    if (self.ptr == self.limit) {
                        self.ptr = start_quote;
                        return error.UnclosedDoubleQuote;
                    }
                    // TODO: do I allow all characters within double quotes?
                    // TODO: the escape check isn't right
                    if (self.ptr[0] == '"' and (self.ptr-1)[0] != '\\') {
                        state_stack.pop();
                    }
                },
                .tick_quoting => |start_quote| {
                    if (self.ptr == self.limit) {
                        self.ptr = start_quote;
                        return error.UnclosedTickQuote;
                    }
                    // TODO: do I allow all characters within tick quotes?
                    // TODO: the escape check isn't right
                    if (self.ptr[0] == '`' and (self.ptr-1)[0] != '\\') {
                        state_stack.pop();
                    }
                },
                .paren => |start_paren| {
                    if (self.ptr == self.limit) {
                        self.ptr = start_paren;
                        return error.UnclosedParen;
                    }
                    // TODO: do I allow all characters within parens?
                    // TODO: the escape check isn't right
                    if (self.ptr[0] == ')' and (self.ptr-1)[0] != '\\') {
                        state_stack.pop();
                    }
                },
            }
        }
    }
    fn scanHeredoc(self: *Lexer, op: HeredocOp) LexError!Token {
        _ = self;
        _ = op;
        @panic("not impl");
    }
};
