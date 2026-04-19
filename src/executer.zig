const parser = @import("parser.zig");
const builtins = @import("builtins.zig");

pub fn exec(p: *parser.Parser, idx: u32) !u8 {
    const node = p.nodes.items[idx];
    switch (node) {
        .command => |argv| {},
        .logical_and => |pair| {},
        .logical_or => |pair| {},
    }
}

// for (commands) |command| {
//     try switch (builtins.parseBuiltin(command)) {
//         .exit => builtins.doExit(command, allocator),
//         .echo => builtins.doEcho(command, allocator),
//         .type => builtins.doType(command, allocator),
//         .pwd => builtins.doPwd(command, allocator),
//         .cd => builtins.doCd(command, allocator),
//         .unknown => builtins.doUnknown(command, allocator),
//     };
// }
