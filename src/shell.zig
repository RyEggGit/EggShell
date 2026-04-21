const std = @import("std");

pub const Shell = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    stdout: *std.Io.Writer,
    stdin: *std.Io.Reader,
    env: *std.process.Environ.Map,

    pub fn home(self: *const Shell) []const u8 {
        return self.env.get("HOME") orelse "";
    }

    pub fn path(self: *const Shell) []const u8 {
        return self.env.get("PATH") orelse "";
    }
};
