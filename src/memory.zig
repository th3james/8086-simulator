const std = @import("std");
const assert = std.debug.assert;

pub const Memory = struct {
    bytes: [1024 * 1024]u8,
};

pub const MemoryWindow = struct {
    start: u32,
    length: u32,
};

pub fn sliceMemory(memory: *Memory, start: u32, end: u32) []u8 {
    assert(end > start);
    const result = memory.*.bytes[start..end];
    assert(result.len > 0);
    return result;
}

pub fn loadFromFile(file_path: []const u8, out: *Memory) !u32 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const bytes_read = try file.read(&out.bytes);
    assert(bytes_read >= 0);
    assert(bytes_read <= out.bytes.len);

    return @intCast(bytes_read);
}

test "sliceMemory returns a window" {
    const allocator = std.testing.allocator;
    const mem = try allocator.create(Memory);
    defer _ = allocator.destroy(mem);

    mem.bytes[3] = 5;
    mem.bytes[4] = 6;

    const result = sliceMemory(mem, 3, 5);

    try std.testing.expectEqual(result[0], 5);
    try std.testing.expectEqual(result[1], 6);
    try std.testing.expectEqual(result.len, 2);
}
