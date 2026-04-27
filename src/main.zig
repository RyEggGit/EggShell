// Copyright 2026 Ryan Eggens

const std = @import("std");
const signals = @import("signals.zig");
const parser = @import("parser.zig");
const executer = @import("executer.zig");
const shell = @import("shell.zig");

const backspace = 127;
const enter = 10;
const esc = '\x1b';

const PROMPT = "$ ";

fn ctrlKey(k: u8) u8 {
    return k & 0x1f;
}

fn clearScreen(out: *std.Io.Writer) !void {
    try out.writeAll("\x1b[2J\x1b[H");
}

fn redraw(out: *std.Io.Writer, line: []const u8, cursor: usize) !void {
    try out.print("\r\x1b[K{s}{s}\r\x1b[{d}C", .{ PROMPT, line, PROMPT.len + cursor });
    try out.flush();
}

fn prevWordBoundary(line: []const u8, cursor: usize) usize {
    var i = cursor;
    while (i > 0 and line[i - 1] == ' ') : (i -= 1) {}
    while (i > 0 and line[i - 1] != ' ') : (i -= 1) {}
    return i;
}

fn nextWordBoundary(line: []const u8, cursor: usize) usize {
    var i = cursor;
    while (i < line.len and line[i] == ' ') : (i += 1) {}
    while (i < line.len and line[i] != ' ') : (i += 1) {}
    return i;
}

fn enableRawMode(old_mode: std.posix.termios) !void {
    var raw_mode = old_mode;
    // Must be false to read ctrl-Q correctly.
    raw_mode.iflag.IXON = false;

    // Make sure that Enter sends 10 and not 13.
    raw_mode.iflag.ICRNL = true;

    // Random things a person said to turn off.
    raw_mode.iflag.BRKINT = false;
    raw_mode.iflag.INPCK = false;
    raw_mode.iflag.ISTRIP = false;

    raw_mode.oflag.OPOST = false;

    raw_mode.lflag.ECHO = false;
    raw_mode.lflag.ICANON = false;
    raw_mode.lflag.ISIG = false;

    // disable Ctrl-O on macOS and Ctrl-V
    raw_mode.lflag.IEXTEN = false;

    raw_mode.cc[@intFromEnum(std.posix.V.MIN)] = 0; // Min chars for non-canonical read
    raw_mode.cc[@intFromEnum(std.posix.V.TIME)] = 1; // Timeout for non-canonical read

    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw_mode);
}

fn readLine(s: *shell.Shell) !?[]u8 {
    var cursor: usize = 0;
    var line = try std.ArrayList(u8).initCapacity(s.allocator, 128);

    const old_mode = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    try enableRawMode(old_mode);
    defer std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, old_mode) catch {};

    try redraw(s.stdout, line.items, cursor);

    var buf: [1]u8 = undefined;
    while (true) {
        const n = try std.posix.read(std.posix.STDIN_FILENO, &buf);
        if (n == 0) continue;

        if (std.ascii.isControl(buf[0]) or buf[0] == esc) {
            switch (buf[0]) {
                ctrlKey('c') => {
                    line.clearRetainingCapacity();
                    cursor = 0;
                    try s.stdout.writeAll("\r\n");
                },
                ctrlKey('d') => {
                    if (line.items.len == 0) {
                        try s.stdout.writeAll("\r\n");
                        try s.stdout.flush();
                        return null;
                    }
                },
                ctrlKey('a') => cursor = 0,
                ctrlKey('e') => cursor = line.items.len,
                ctrlKey('l') => try clearScreen(s.stdout),
                backspace, ctrlKey('h') => {
                    if (cursor > 0) {
                        _ = line.orderedRemove(cursor - 1);
                        cursor -= 1;
                    }
                },
                esc => {
                    var seq: [2]u8 = undefined;
                    const num = try std.posix.read(std.posix.STDIN_FILENO, &seq);

                    if (num == 1) {
                        // alt pressed
                        switch (seq[0]) {
                            'b' => cursor = prevWordBoundary(line.items, cursor),
                            'f' => cursor = nextWordBoundary(line.items, cursor),
                            0x7f => {
                                if (cursor > 0) {
                                    const prev = cursor;
                                    cursor = prevWordBoundary(line.items, cursor);
                                    try line.replaceRange(s.allocator, cursor, prev - cursor, "");
                                }
                            },
                            else => {},
                        }
                    } else if (num >= 2 and seq[0] == '[') switch (seq[1]) {
                        'D' => if (cursor > 0) {
                            cursor -= 1;
                        },
                        'C' => if (cursor < line.items.len) {
                            cursor += 1;
                        },
                        else => {},
                    };
                },
                enter => {
                    try s.stdout.writeAll("\r\n");
                    try s.stdout.flush();
                    return try line.toOwnedSlice(s.allocator);
                },
                else => {},
            }
        } else {
            try line.insert(s.allocator, cursor, buf[0]);
            cursor += 1;
        }

        try redraw(s.stdout, line.items, cursor);
    }
}

var stdout_buffer: [4096]u8 = undefined;
var stdin_buffer: [4096]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = init.arena;
    defer arena.deinit();

    signals.register();

    var stdout_writer = std.Io.File.writerStreaming(std.Io.File.stdout(), io, &stdout_buffer);
    var stdin_reader = std.Io.File.readerStreaming(std.Io.File.stdin(), io, &stdin_buffer);

    var s = shell.Shell{
        .allocator = arena.allocator(),
        .stdout = &stdout_writer.interface,
        .stdin = &stdin_reader.interface,
        .io = io,
        .env = init.environ_map,
    };

    while (true) {
        const input = try readLine(&s) orelse std.process.exit(0);
        const tokens = try parser.lex(input, s.allocator);
        defer s.allocator.free(tokens);
        var p = parser.Parser.new(s.allocator, tokens);
        const node = try p.parse();

        const retval = try executer.exec(&s, &p, node);

        if (retval != 0) {
            std.process.exit(retval);
        }
    }
}
