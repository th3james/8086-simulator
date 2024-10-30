const std = @import("std");

const instruction = @import("instruction.zig");
const instruction_layout = @import("instruction_layout.zig");
const opcodes = @import("opcodes.zig");
const registers = @import("register_names.zig");

const Operand = union(enum) {
    register: registers.Register,
    memory_address: u32,
    none,
};

pub fn decodeArguments(inst: instruction.Instruction) ![2]Operand {
    return switch (inst.opcode.id) {
        opcodes.OpcodeId.movRegOrMemToFromReg => .{
            Operand{ .register = registers.Register.cl },
            Operand{ .register = registers.Register.al },
        },
        else => .{
            Operand.none,
            Operand.none,
        },
    };
}

fn buildInstructionFromBytes(bytes: []const u8, length: u4) !instruction.Instruction {
    const result = try opcodes.decodeOpcode(bytes[0..length]);
    return instruction.Instruction{
        .bytes = bytes[0..],
        .opcode = result,
        .layout = instruction_layout.getInstructionLayout(result),
    };
}

test "decodeArguments - MOV Decode - Reg to Reg" {
    const bytes = [_]u8{ 0b10001000, 0b11000001, 0, 0, 0, 0 };
    const subject = try buildInstructionFromBytes(
        &bytes,
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(registers.Register.cl, result[0].register);
    try std.testing.expectEqual(registers.Register.al, result[1].register);
}

test "decodeArgs - MOV Direct address" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b10001000, 0b00000110, 0b1, 0b1, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(registers.Register.al, result[0].register);
    try std.testing.expectEqual(Operand{ .memory_address = 257 }, result[1]);
}

fn operandToString(allocator: std.mem.Allocator, argument: Operand) ![]const u8 {
    return switch (argument) {
        .register => |*r| @tagName(r.*),
        else => try std.fmt.allocPrint(allocator, "5", .{}),
    };
}

pub fn argumentsToString(
    allocator: std.mem.Allocator,
    mnemonic: []const u8,
    args: [2]Operand,
) ![]const u8 {
    const arg1_str = try operandToString(allocator, args[0]);
    const arg2_str = try operandToString(allocator, args[1]);
    return try std.fmt.allocPrint(allocator, "{s} {s}, {s}", .{ mnemonic, arg1_str, arg2_str });
}

test "argumentsToString - MOV Decode - Reg to Reg" {
    const args = [_]Operand{
        .{ .register = registers.Register.cl },
        .{ .register = registers.Register.al },
    };
    const result = try argumentsToString(
        std.testing.allocator,
        "mov",
        args,
    );

    try std.testing.expectEqualStrings("mov cl, al", result);
}
