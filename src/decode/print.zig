const std = @import("std");

const decode_arguments = @import("arguments.zig");
const registers = @import("register_names.zig");

fn operandToString(writer: anytype, argument: decode_arguments.Operand) !void {
    switch (argument) {
        .register => |*r| {
            try writer.writeAll(@tagName(r.*));
        },
        .relative_address => |*a| {
            try writer.writeAll("[");
            try std.fmt.formatInt(
                @abs(a.*),
                10,
                .lower,
                .{},
                writer,
            );
            try writer.writeAll("]");
        },
        else => {
            try writer.writeAll("welp");
        },
    }
}

// cp ax, bx
const MIN_INSTRUCTION_STR_LEN = 9;
pub fn instructionToString(
    allocator: std.mem.Allocator,
    mnemonic: []const u8,
    args: [2]decode_arguments.Operand,
) ![]const u8 {
    var result_buffer = try std.ArrayList(u8).initCapacity(allocator, MIN_INSTRUCTION_STR_LEN);
    errdefer result_buffer.deinit();

    const writer = result_buffer.writer();

    try writer.writeAll(mnemonic);
    try writer.writeAll(" ");

    try operandToString(writer, args[0]);
    try writer.writeAll(", ");
    try operandToString(writer, args[1]);

    return result_buffer.toOwnedSlice();
}

test "instructionToString - register arguments" {
    const allocator = std.testing.allocator;
    const args = [_]decode_arguments.Operand{
        .{ .register = registers.Register.cl },
        .{ .register = registers.Register.al },
    };
    const result = try instructionToString(
        std.testing.allocator,
        "mov",
        args,
    );
    defer allocator.free(result);

    try std.testing.expectEqualStrings("mov cl, al", result);
}

test "instructionToString - relative address arguments" {
    const allocator = std.testing.allocator;
    const args = [_]decode_arguments.Operand{
        .{ .register = registers.Register.al },
        .{ .relative_address = 257 },
    };
    const result = try instructionToString(
        std.testing.allocator,
        "mov",
        args,
    );
    defer allocator.free(result);

    try std.testing.expectEqualStrings("mov al, [257]", result);
}
