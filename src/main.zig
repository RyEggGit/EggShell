// Copyright 2026 Ryan Eggens

const std = @import("std");
const signals = @import("signals.zig");
const parser = @import("parser.zig");
const executer = @import("executer.zig");
const shell = @import("shell.zig");

var stdout_buffer: [4096]u8 = undefined;
var stdin_buffer: [4096]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = init.arena;
    defer arena.deinit();

    signals.register(io);

    var stdout_writer = std.Io.File.writerStreaming(std.Io.File.stdout(), io, &stdout_buffer);
    var stdin_reader = std.Io.File.readerStreaming(std.Io.File.stdin(), io, &stdin_buffer);

    var s = shell.Shell{
        .allocator = arena.allocator(),
        .stdout = &stdout_writer.interface,
        .stdin = &stdin_reader.interface,
        .env = init.environ_map,
    };

    while (true) {
        try s.stdout.print("$ ", .{});
        const input = try s.stdin.takeDelimiter('\n') orelse {
            try s.stdout.print("\n", .{});
            std.process.exit(0);
        };
        const tokens = try parser.lex(input, s.allocator);
        defer s.allocator.free(tokens);
        var p = parser.Parser.new(s.allocator, tokens);
        const node = try p.parse();

        try executer.exec(&s, &p, node);
    }
}
