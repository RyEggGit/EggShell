// NOTE: Was removed in version 0.15 (current version at the time), which is why written by hand
// simple implementation of: https://ziglang.org/documentation/0.14.0/std/#src/std/RingBuffer.zig

const std = @import("std");
const testing = std.testing;

/// Standard Ring Buffer
pub fn RingBuffer(comptime T: type, comptime size: usize) type {
    return struct {
        buffer: [size]T,
        head:   usize,
        count:  usize,

        const Self = @This();

        pub fn init() Self {
            return .{
                .buffer = undefined,
                .head   = 0,
                .count  = 0,
            };
        }

        pub fn push(self: *Self, item: T) ?T {
            const slot = (self.head + self.count) % size;

            if (self.count == size) {
                // full — evict oldest, return it so caller can clean up
                const evicted = self.buffer[self.head];
                self.head = (self.head + 1) % size;
                self.buffer[slot] = item;
                return evicted;
            } else {
                self.buffer[slot] = item;
                self.count += 1;
                return null;
            }
        }

        pub fn get(self: *Self, index: usize) ?T {
            if (index >= self.count) return null;
            return self.buffer[(self.head + index) % size];
        }
    };
}


test "push and get" {
    var rb = RingBuffer(i32, 4).init();
    _ = rb.push(1);
    _ = rb.push(2);
    _ = rb.push(3);

    try testing.expectEqual(@as(i32, 1), rb.get(0).?);
    try testing.expectEqual(@as(i32, 2), rb.get(1).?);
    try testing.expectEqual(@as(i32, 3), rb.get(2).?);
}

test "evicts oldest when full" {
    var rb = RingBuffer(i32, 3).init();
    _ = rb.push(1);
    _ = rb.push(2);
    _ = rb.push(3);
    const evicted = rb.push(4);

    try testing.expectEqual(@as(i32, 1), evicted.?);
    try testing.expectEqual(@as(i32, 2), rb.get(0).?);
    try testing.expectEqual(@as(i32, 4), rb.get(2).?);
    try testing.expectEqual(@as(usize, 3), rb.count);
}

test "get out of bounds returns null" {
    var rb = RingBuffer(i32, 4).init();
    _ = rb.push(1);

    try testing.expectEqual(@as(?i32, null), rb.get(1));
    try testing.expectEqual(@as(?i32, null), rb.get(99));
}
