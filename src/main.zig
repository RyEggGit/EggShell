// Copyright 2026 Ryan Eggens

const std = @import("std");
const signals = @import("signals.zig");
const parser = @import("parser.zig");
const executer = @import("executer.zig");

var stdout_buffer: [4096]u8 = undefined;
var stdin_buffer: [4096]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    signals.register(io);

    var stdout_writer = std.Io.File.writerStreaming(std.Io.File.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    var stdin_reader = std.Io.File.readerStreaming(std.Io.File.stdin(), io, &stdin_buffer);
    const stdin = &stdin_reader.interface;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    while (true) {
        try stdout.print("$ ", .{});
        const input = try stdin.takeDelimiter('\n') orelse {
            try stdout.print("\n", .{});
            std.process.exit(0);
        };
        const tokens = try parser.lex(input, allocator);
        defer allocator.free(tokens);
        var p = parser.Parser.new(allocator, tokens);
        const node = try p.parse();

        try executer.exec(&p, node);
    }
}
