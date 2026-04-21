const std = @import("std");
const parser = @import("parser.zig");
const Command = parser.Command;
const Shell = @import("shell.zig").Shell;

const Builtin = enum {
    exit,
    echo,
    type,
    cd,
    pwd,
    unknown,
};

pub fn parseBuiltin(command: Command) Builtin {
    const cmd = command[0];
    if (std.mem.eql(u8, cmd, "exit")) return .exit;
    if (std.mem.eql(u8, cmd, "pwd")) return .pwd;
    if (std.mem.eql(u8, cmd, "cd")) return .cd;
    if (std.mem.eql(u8, cmd, "echo")) return .echo;
    if (std.mem.eql(u8, cmd, "type")) return .type;
    return .unknown;
}

pub fn doExit(_: *Shell, _: Command) noreturn {
    std.process.exit(0);
}

pub fn doEcho(self: *Shell, command: Command) !void {
    const args = try std.mem.join(self.allocator, " ", command[1..]);
    try self.stdout.print("{s}\n", .{args});
}

pub fn doType(self: *Shell, command: Command) !void {
    // TODO: bring this functionality back
    const arg = command[1];
    // if (parseBuiltin(arg) != .unknown) {
    //     try self.stdout.print("{s} is a shell builtin\n", .{arg});
    //     return;
    // }

    if (try findMatchingPath(self, arg)) |match| {
        try self.stdout.print("{s} is {s}\n", .{ arg, match });
    } else {
        try self.stdout.print("{s}: not found\n", .{arg});
    }
}

pub fn doPwd(self: *Shell, _: Command) !void {
    const path = try std.process.currentPathAlloc(self.io, self.allocator);
    defer self.allocator.free(path);
    try self.stdout.print("{s}\n", .{path});
}

pub fn doCd(self: *Shell, command: Command) !void {
    var path = self.home();

    if (command.len > 1) {
        path = command[1];
    }

    if (std.mem.eql(u8, path, "~")) {
        path = self.home();
    }

    // This handles relative paths like ".."
    if (std.Io.Dir.openDir(.cwd(), self.io, path, .{})) |d| {
        var dir = d;
        defer dir.close(self.io);
        try std.process.setCurrentDir(self.io, dir);
    } else |_| {
        try self.stdout.print("{s}: No such file or directory\n", .{command[1]});
    }
}

pub fn doUnknown(self: *Shell, command: Command) !void {
    if (try findMatchingPath(self, command[0])) |_| {
        const response = try execute(self, command);
        if (response != 0) {
            try self.stdout.print("{s}: failed with status code {d}\n", .{ command[0], response });
        }
    } else {
        try self.stdout.print("{s}: command not found\n", .{command[0]});
    }
}

// for a command check if it exists in path
fn findMatchingPath(self: *Shell, command: []const u8) !?[]const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(self.allocator);

    var it = std.mem.splitSequence(u8, self.path(), ":");
    while (it.next()) |p| {
        const copy = try self.allocator.dupe(u8, p);
        try paths.append(self.allocator, copy);
    }

    for (paths.items) |path| {
        const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ path, command });
        if (std.Io.Dir.accessAbsolute(self.io, full_path, .{})) {
            return full_path;
        } else |_| {}
    }
    return null;
}

// Execute an arbritary command in the current terminal window (ex: pwd,..)
fn execute(self: *Shell, command: []const []const u8) !u8 {
    var child = try std.process.spawn(self.io, .{
        .argv = command,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    return switch (try child.wait(self.io)) {
        .exited => |code| code,
        .signal => |sig| blk: {
            std.debug.print("killed by signal {d}\n", .{sig});
            break :blk 1;
        },
        .stopped => 1,
        .unknown => 1,
    };
}
