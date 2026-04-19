const std = @import("std");

var stdout_buffer: [4096]u8 = undefined;
var stdout: ?*std.Io.Writer = null;

fn onSigint(_: std.posix.SIG) callconv(.c) void {
    if (stdout) |w| {
        w.print("\n\n$ ", .{}) catch {};
    }
}

fn onSigterm(_: std.posix.SIG) callconv(.c) void {
    std.process.exit(0);
}

pub fn register(io: std.Io) void {
    var w = std.Io.File.writerStreaming(std.Io.File.stdout(), io, &stdout_buffer);
    stdout = &w.interface; // still wrong — see note

    const mask = std.posix.sigemptyset();
    std.posix.sigaction(std.posix.SIG.INT, &action(onSigint, mask), null);
    std.posix.sigaction(std.posix.SIG.TERM, &action(onSigterm, mask), null);
    std.posix.sigaction(std.posix.SIG.TSTP, &ignore(mask), null);
}

fn action(comptime f: fn (std.posix.SIG) callconv(.c) void, mask: std.posix.sigset_t) std.posix.Sigaction {
    return .{
        .handler = .{ .handler = f },
        .mask = mask,
        .flags = 0,
    };
}

fn ignore(mask: std.posix.sigset_t) std.posix.Sigaction {
    return .{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = mask,
        .flags = 0,
    };
}
