const std = @import("std");
const parser = @import("parser.zig");
const builtins = @import("builtins.zig");
const Shell = @import("shell.zig").Shell;

pub fn exec(self: *Shell, p: *parser.Parser, idx: u32) !u8 {
    const node = p.nodes.items[idx];
    switch (node) {
        .command => |argv| {
            if (argv.len == 0) {
                return 0;
            } else {
                try switch (builtins.parseBuiltin(argv)) {
                    .exit => builtins.doExit(self, argv),
                    .echo => builtins.doEcho(self, argv),
                    .type => builtins.doType(self, argv),
                    .pwd => builtins.doPwd(self, argv),
                    .cd => builtins.doCd(self, argv),
                    .unknown => builtins.doUnknown(self, argv),
                };
            }
        },
        .logical_and => |pair| {
            if (try exec(self, p, pair.left) == 0) {
                return try exec(self, p, pair.right);
            } else {
                return 1;
            }
        },
        .logical_or => |pair| {
            if (try exec(self, p, pair.left) == 0) {
                return 0;
            } else {
                return try exec(self, p, pair.right);
            }
        },
    }

    return 0;
}
