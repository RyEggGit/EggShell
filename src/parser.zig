const std = @import("std");
const testing = std.testing;

const Token = union(enum) {
    word: []const u8,
    pipe, // |
    logical_or, // ||
    background, // &
    logical_and, // &&
};

const Command = []const []const u8;
const Commands = []Command;

const Node = union(enum) {
    // pipe(Node, Node),
    logical_or: struct { *const Node, *const Node },
    logical_and: struct { *const Node, *const Node },
    // background(Node),
    command: Command,
};

fn isSpecialCharacter(c: u8) bool {
    return switch (c) {
        ' ', '\n', '"', '|' => true,
        else => false,
    };
}

fn lex(input: []const u8, allocator: std.mem.Allocator) ![]Token {
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

const Parser = struct {
    gpa: std.mem.Allocator,
    tok_i: u64,
    tokens: []Token,

    fn peek(self: *Parser) Token {
        return self.tokens[self.tok_i];
    }

    fn consume(self: *Parser) Token {
        const token = self.peek();
        self.tok_i += 1;
        return token;
    }

    // foo || bar -> LogicalOr{ Command{ .{ "foo" } }, Command{ .{ "bar" } } }
    fn parserOr(self: *Parser) !Node {
        var left: Node = try self.parseAnd();

        while (self.tok_i < self.tokens.len and self.peek() == .logical_or) {
            _ = self.consume();
            const right = try self.parseAnd();
            const left_ptr = try self.gpa.create(Node);
            const right_ptr = try self.gpa.create(Node);
            left_ptr.* = left;
            right_ptr.* = right;
            left = Node{ .logical_or = .{ left_ptr, right_ptr } };
        }

        return left;
    }

    // foo && bar -> LogicalAnd{ Command{ .{ "foo" } }, Command{ .{ "bar" } } }
    fn parseAnd(self: *Parser) !Node {
        var left: Node = try self.parseCommand();

        while (self.tok_i < self.tokens.len and self.peek() == .logical_and) {
            _ = self.consume();
            const right = try self.parseCommand();
            const left_ptr = try self.gpa.create(Node);
            const right_ptr = try self.gpa.create(Node);
            left_ptr.* = left;
            right_ptr.* = right;
            left = Node{ .logical_and = .{ left_ptr, right_ptr } };
        }

        return left;
    }

    // echo --foo --bar "baz" -> Command{ .{ "echo", "--foo", "--bar", "baz" } }
    fn parseCommand(self: *Parser) !Node {
        var argv: std.ArrayList([]const u8) = .empty;

        while (self.tok_i < self.tokens.len and self.peek() == .word) {
            const token = self.consume();
            try argv.append(self.gpa, token.word);
        }

        return Node{ .command = try argv.toOwnedSlice(self.gpa) };
    }
};

// fn parse(tokens: []Token, allocator: std.mem.Allocator) !Commands {
//     var commands: std.ArrayList(Command) = .empty;
//     var current: std.ArrayList([]const u8) = .empty;

//     for (tokens) |t| {
//         switch (t) {
//             .word => |w| try current.append(allocator, w),
//         }
//     }

//     // last command
//     if (current.items.len > 0) {
//         try commands.append(allocator, try current.toOwnedSlice(allocator));
//     }

//     return try commands.toOwnedSlice(allocator);
// }

pub fn parseCommands(input: []const u8, allocator: std.mem.Allocator) !Node {
    const tokens = try lex(input, allocator);
    var parser = Parser{
        .gpa = allocator,
        .tok_i = 0,
        .tokens = tokens,
    };
    return try parser.parserOr();
}

// Testing helper function.
fn expectTokens(input: []const u8, expected: []const Token) !void {
    const tokens = try lex(input, testing.allocator);
    defer testing.allocator.free(tokens);
    try testing.expectEqualDeep(expected, tokens);
}

fn freeNode(allocator: std.mem.Allocator, node: Node) void {
    switch (node) {
        .command => |cmd| allocator.free(cmd),
        .logical_and, .logical_or => |pair| {
            freeNode(allocator, pair[0].*);
            freeNode(allocator, pair[1].*);
            allocator.destroy(pair[0]);
            allocator.destroy(pair[1]);
        },
    }
}

fn expectCommands(input: []const u8, expected: Node) !void {
    const tokens = try lex(input, testing.allocator);
    defer testing.allocator.free(tokens);
    var parser = Parser{
        .gpa = testing.allocator,
        .tok_i = 0,
        .tokens = tokens,
    };
    const commands = try parser.parserOr();
    defer freeNode(testing.allocator, commands);
    try testing.expectEqualDeep(expected, commands);
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

test "parse commands" {
    try expectCommands(
        "echo hello && echo bye",
        Node{ .logical_and = .{
            &Node{ .command = &.{ "echo", "hello" } },
            &Node{ .command = &.{ "echo", "bye" } },
        } },
    );
}
