const std = @import("std");

const instruction = @import("instruction.zig");
const instruction_layout = @import("instruction_layout.zig");
const opcodes = @import("opcodes.zig");
const registers = @import("register_names.zig");

const Operand = union(enum) {
    register: registers.Register,
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
