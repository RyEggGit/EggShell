const std = @import("std");

fn onSigint(_: std.posix.SIG) callconv(.c) void {
    const msg = "\n$ ";
    _ = std.posix.system.write(std.posix.STDOUT_FILENO, msg.ptr, msg.len);
}

fn onSigterm(_: std.posix.SIG) callconv(.c) void {
    std.process.exit(0);
}

pub fn register() void {
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
