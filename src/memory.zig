const std = @import("std");
const assert = std.debug.assert;

pub const Memory = struct {
    bytes: [1024 * 1024]u8,

    pub fn read(self: *const Memory, address: u32) u8 {
        assert(address < self.bytes.len);
        return self.bytes[address];
    }
};

pub fn loadFromFile(file_path: []const u8, out: *Memory) !u32 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const bytes_read = try file.read(&out.bytes);
    assert(bytes_read >= 0);
    assert(bytes_read <= out.bytes.len);

    return @intCast(bytes_read);
}

test "Memory.read returns data at offset" {
    const allocator = std.testing.allocator;
    const subject = try allocator.create(Memory);
    defer _ = allocator.destroy(subject);

    subject.bytes[3] = 4;

    try std.testing.expectEqual(subject.read(3), 4);
}
