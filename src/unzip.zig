const builtin = @import("builtin");
const std = @import("std");

fn oom(e: error{OutOfMemory}) noreturn {
    @panic(@errorName(e));
}
fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(0xff);
}

fn usage(io: std.Io) !void {
    try std.Io.File.stderr().writeStreamingAll(
        io,
        "Usage: unzip [-d DIR] ZIP_FILE\n",
    );
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const cwd = std.Io.Dir.cwd();

    var cmdline_opt: struct {
        dir_arg: ?[:0]const u8 = null,
    } = .{};

    const cmd_args = blk: {
        const cmd_args = try init.minimal.args.toSlice(arena);
        var non_options = std.ArrayList([:0]const u8).empty;
        var arg_index: usize = 1;
        while (arg_index < cmd_args.len) : (arg_index += 1) {
            const arg = cmd_args[arg_index];
            if (!std.mem.startsWith(u8, arg, "-")) {
                try non_options.append(arena, arg);
            } else if (std.mem.eql(u8, arg, "-d")) {
                arg_index += 1;
                if (arg_index == cmd_args.len)
                    fatal("option '{s}' requires an argument", .{arg});
                cmdline_opt.dir_arg = cmd_args[arg_index];
            } else {
                fatal("unknown cmdline option '{s}'", .{arg});
            }
        }
        break :blk try non_options.toOwnedSlice(arena);
    };

    if (cmd_args.len != 1) {
        try usage(io);
        std.process.exit(0xff);
    }
    const zip_file_arg = cmd_args[0];

    var out_dir = blk: {
        if (cmdline_opt.dir_arg) |dir| {
            break :blk cwd.openDir(io, dir, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    try cwd.createDirPath(io, dir);
                    break :blk try cwd.openDir(io, dir, .{});
                },
                else => fatal("failed to open output directory '{s}' with {s}", .{ dir, @errorName(err) }),
            };
        }
        break :blk cwd;
    };
    defer if (cmdline_opt.dir_arg) |_| out_dir.close(io);

    const zip_file = cwd.openFile(io, zip_file_arg, .{}) catch |err|
        fatal("open '{s}' failed: {s}", .{ zip_file_arg, @errorName(err) });
    defer zip_file.close(io);
    var buffer: [4096]u8 = undefined;
    var reader = zip_file.reader(io, &buffer);
    try std.zip.extract(out_dir, &reader, .{
        .allow_backslashes = true,
    });
}
