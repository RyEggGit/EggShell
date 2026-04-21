const std = @import("std");
const testing = std.testing;

const Token = union(enum) {
    word: []const u8,
    pipe, // |
    logical_or, // ||
    background, // &
    logical_and, // &&
};

pub const Command = []const []const u8;
pub const Commands = []const Command;

// TODO: Add background, pipe
const Node = union(enum) {
    logical_or: struct { left: u32, right: u32 },
    logical_and: struct { left: u32, right: u32 },
    command: Command,
};

fn isSpecialCharacter(c: u8) bool {
    return switch (c) {
        ' ', '\n', '"', '|' => true,
        else => false,
    };
}

pub fn lex(input: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens: std.ArrayList(Token) = .empty;

    var i: usize = 0;
    while (i < input.len) {
        switch (input[i]) {
            ' ', '\n' => i += 1,
            '"' => {
                const start = i + 1;
                i += 1;
                while (i < input.len and input[i] != '"') : (i += 1) {}
                const str = input[start..i];
                try tokens.append(allocator, .{ .word = str });
                i += 1;
            },
            '|' => {
                if (i + 1 < input.len and input[i + 1] == '|') {
                    try tokens.append(allocator, Token.logical_or);
                    i += 2;
                } else {
                    try tokens.append(allocator, Token.pipe);
                    i += 1;
                }
            },
            '&' => {
                if (i + 1 < input.len and input[i + 1] == '&') {
                    try tokens.append(allocator, Token.logical_and);
                    i += 2;
                } else {
                    try tokens.append(allocator, Token.background);
                    i += 1;
                }
            },
            else => {
                const start = i;
                while (i < input.len and !isSpecialCharacter(input[i])) : (i += 1) {}
                try tokens.append(allocator, .{ .word = input[start..i] });
            },
        }
    }

    return tokens.toOwnedSlice(allocator);
}

pub const Parser = struct {
    gpa: std.mem.Allocator,
    tok_i: u64,
    tokens: []Token,
    nodes: std.ArrayList(Node) = .empty,

    pub fn new(gpa: std.mem.Allocator, tokens: []Token) Parser {
        return Parser{
            .gpa = gpa,
            .tok_i = 0,
            .tokens = tokens,
        };
    }

    fn peek(self: *Parser) Token {
        return self.tokens[self.tok_i];
    }

    fn consume(self: *Parser) Token {
        const token = self.peek();
        self.tok_i += 1;
        return token;
    }

    fn addNode(self: *Parser, node: Node) !u32 {
        const idx: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(self.gpa, node);
        return idx;
    }

    // Return true if the next token is of the same variant as `t`.
    fn expect(self: *Parser, t: Token) bool {
        return self.tok_i < self.tokens.len and std.meta.activeTag(self.peek()) == t;
    }

    pub fn parse(self: *Parser) !u32 {
        return try self.parseOr();
    }

    // foo || bar -> LogicalOr{ Command{ .{ "foo" } }, Command{ .{ "bar" } } }
    fn parseOr(self: *Parser) !u32 {
        var left: u32 = try self.parseAnd();

        while (self.expect(.logical_or)) {
            _ = self.consume();
            const right = try self.parseAnd();
            left = try self.addNode(Node{ .logical_or = .{ .left = left, .right = right } });
        }

        return left;
    }

    // foo && bar -> LogicalAnd{ Command{ .{ "foo" } }, Command{ .{ "bar" } } }
    fn parseAnd(self: *Parser) !u32 {
        var left: u32 = try self.parseCommand();

        while (self.expect(.logical_and)) {
            _ = self.consume();
            const right = try self.parseCommand();
            left = try self.addNode(Node{ .logical_and = .{ .left = left, .right = right } });
        }

        return left;
    }

    // echo --foo --bar "baz" -> Command{ .{ "echo", "--foo", "--bar", "baz" } }
    fn parseCommand(self: *Parser) !u32 {
        var argv: std.ArrayList([]const u8) = .empty;

        while (self.tok_i < self.tokens.len and std.meta.activeTag(self.peek()) == .word) {
            const token = self.consume();
            try argv.append(self.gpa, token.word);
        }

        const n = Node{ .command = try argv.toOwnedSlice(self.gpa) };
        return self.addNode(n);
    }

    // For debugging and snap tests.
    fn printNode(self: *const Parser, writer: anytype, idx: u32) !void {
        const node = self.nodes.items[idx];
        switch (node) {
            .command => |argv| {
                try writer.writeAll("[");
                for (argv, 0..) |arg, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.writeAll(arg);
                }
                try writer.writeAll("]");
            },
            .logical_and => |pair| {
                try writer.writeAll("(and ");
                try self.printNode(writer, pair.left);
                try writer.writeAll(" ");
                try self.printNode(writer, pair.right);
                try writer.writeAll(")");
            },
            .logical_or => |pair| {
                try writer.writeAll("(or ");
                try self.printNode(writer, pair.left);
                try writer.writeAll(" ");
                try self.printNode(writer, pair.right);
                try writer.writeAll(")");
            },
        }
    }
};

pub fn parseCommands(input: []const u8, allocator: std.mem.Allocator) !struct { u32, []Node } {
    const tokens = try lex(input, allocator);
    var parser = Parser{
        .gpa = allocator,
        .tok_i = 0,
        .tokens = tokens,
    };
    const root = try parser.parseOr();
    return .{ root, try parser.nodes.toOwnedSlice(allocator) };
}

// Testing helper function.
fn expectTokens(input: []const u8, expected: []const Token) !void {
    const tokens = try lex(input, testing.allocator);
    defer testing.allocator.free(tokens);
    try testing.expectEqualDeep(expected, tokens);
}

test "canonical example" {
    try expectTokens("echo hello world", &.{
        .{ .word = "echo" },
        .{ .word = "hello" },
        .{ .word = "world" },
    });
}

test "quotes" {
    try expectTokens("echo \"hello world\"", &.{
        .{ .word = "echo" },
        .{ .word = "hello world" },
    });
}

test "flags" {
    try expectTokens("compile --drafts main.mk", &.{
        .{ .word = "compile" },
        .{ .word = "--drafts" },
        .{ .word = "main.mk" },
    });
}

test "dot slash" {
    try expectTokens("./a.out", &.{
        .{ .word = "./a.out" },
    });
}

// TODO: Decide if an unmatched quote should be an error or if it should just assume until \n is the quote.
test "unmatched quote" {
    try expectTokens("echo \"hello world", &.{
        .{ .word = "echo" },
        .{ .word = "hello world" },
    });
}

test "leading and trailing spaces" {
    try expectTokens("   echo hello world   ", &.{ .{ .word = "echo" }, .{ .word = "hello" }, .{
        .word = "world",
    } });
}

test "pipes and logical operators" {
    try expectTokens(
        "echo hello | grep h && echo done &",
        &.{
            .{ .word = "echo" },
            .{ .word = "hello" },
            .pipe,
            .{ .word = "grep" },
            .{ .word = "h" },
            .logical_and,
            .{ .word = "echo" },
            .{ .word = "done" },
            .background,
        },
    );
}

const Snap = @import("snaptest.zig").Snap;
const snap = Snap.snap;

fn checkTree(input: []const u8, want: Snap) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tokens = try lex(input, allocator);
    var parser = Parser.new(allocator, tokens);
    const root = try parser.parse();
    var aw: std.Io.Writer.Allocating = .init(allocator);
    try parser.printNode(&aw.writer, root);
    try want.diff(aw.writer.buffered());
}

test "snap: simple command" {
    try checkTree("echo hello world", snap(@src(),
        \\[echo, hello, world]
    ));
}

test "snap: logical and" {
    try checkTree("echo hello && echo bye", snap(@src(),
        \\(and [echo, hello] [echo, bye])
    ));
}

test "snap: operator precedence" {
    try checkTree("echo meep || echo hello && echo bye", snap(@src(),
        \\(or [echo, meep] (and [echo, hello] [echo, bye]))
    ));
}

test "snap: ambiguous symbols" {
    try checkTree("echo meep || \"||\"", snap(@src(),
        \\(or [echo, meep] [||])
    ));
}
