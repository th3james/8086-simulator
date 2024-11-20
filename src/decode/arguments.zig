const std = @import("std");

const instruction = @import("instruction.zig");
const instruction_layout = @import("instruction_layout.zig");
const opcodes = @import("opcodes.zig");
const registers = @import("register_names.zig");
const errors = @import("errors.zig");

pub const Operand = union(enum) {
    register: registers.Register,
    relative_address: i16,
    immediate: i16, // TODO might need an unsigned variant?
    effective_address: registers.EffectiveAddress,
    none,
};

pub fn decodeArguments(inst: instruction.Instruction) ![2]Operand {
    switch (inst.opcode.id) {
        opcodes.OpcodeId.movRegOrMemToFromReg => {
            switch (opcodes.Mode.fromInt(inst.opcode.mod.?)) {
                .memory_no_displacement => {
                    if (inst.opcode.regOrMem == 0b110) { // Direct address
                        const reg = registers.getRegister(
                            inst.opcode.reg.?,
                            inst.opcode.wide.?,
                        );

                        return .{
                            Operand{ .register = reg },
                            Operand{ .relative_address = try inst.getDisplacement() },
                        };
                    } else {
                        return .{
                            Operand.none,
                            Operand.none,
                        };
                    }
                },
                .register => {
                    const dest = if (inst.opcode.regIsDestination.?) inst.opcode.reg.? else inst.opcode.regOrMem.?;
                    const source = if (inst.opcode.regIsDestination.?) inst.opcode.regOrMem.? else inst.opcode.reg.?;
                    return .{
                        Operand{ .register = registers.getRegister(dest, inst.opcode.wide.?) },
                        Operand{ .register = registers.getRegister(source, inst.opcode.wide.?) },
                    };
                },
                else => {
                    const reg = registers.getRegister(inst.opcode.reg.?, inst.opcode.wide.?);
                    const effective_address = registers.effectiveAddressRegisters(
                        inst.opcode.regOrMem.?,
                        try inst.getDisplacement(),
                    );
                    if (inst.opcode.regIsDestination orelse false) {
                        return .{
                            Operand{ .register = reg },
                            Operand{ .effective_address = effective_address },
                        };
                    } else {
                        return .{
                            Operand{ .effective_address = effective_address },
                            Operand{ .register = reg },
                        };
                    }
                },
            }
        },

        opcodes.OpcodeId.movImmediateToReg => {
            const reg = registers.getRegister(inst.opcode.reg.?, inst.opcode.wide.?);
            const immediate = try inst.getImmediate();
            return .{
                Operand{ .register = reg },
                Operand{ .immediate = immediate },
            };
        },

        opcodes.OpcodeId.movImmediateToRegOrMem => {
            const effective_address = registers.effectiveAddressRegisters(
                inst.opcode.regOrMem.?,
                inst.getDisplacement() catch |err| switch (err) {
                    errors.InstructionErrors.NoDisplacement => 0,
                    else => {
                        return err;
                    },
                },
            );
            const immediate = try inst.getImmediate();
            return .{
                Operand{ .effective_address = effective_address },
                Operand{ .immediate = immediate },
            };
        },

        else => {
            return .{
                Operand.none,
                Operand.none,
            };
        },
    }
}

fn buildInstructionFromBytes(bytes: []const u8, opcode_length: u4) !instruction.Instruction {
    const result = try opcodes.decodeOpcode(bytes[0..opcode_length]);
    return instruction.Instruction{
        .bytes = bytes[0..],
        .opcode = result,
        .layout = instruction_layout.getInstructionLayout(result),
    };
}

test "decodeArguments - MOV Reg to Reg" {
    const bytes = [_]u8{ 0b10001000, 0b11000001, 0, 0, 0, 0 };
    const subject = try buildInstructionFromBytes(
        &bytes,
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(registers.Register.cl, result[0].register);
    try std.testing.expectEqual(registers.Register.al, result[1].register);
}

test "decodeArguments - MOV Direct address" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b10001000, 0b00000110, 0b1, 0b1, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(registers.Register.al, result[0].register);
    try std.testing.expectEqual(Operand{ .relative_address = 257 }, result[1]);
}

test "decodeArguments - MOV reg or memory" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b1000_1011, 0b0100_0001, 0b1101_1011, 0b0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(registers.Register.ax, result[0].register);
    const expected_address = registers.EffectiveAddress{
        .r1 = registers.Register.bx,
        .r2 = registers.Register.di,
        .displacement = -37,
    };
    try std.testing.expectEqual(expected_address, result[1].effective_address);
}

test "decodeArguments - MOV Decode - Immediate to register narrow positive" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b00000110, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    // TODO next assertion could be wrong
    try std.testing.expectEqual(Operand{ .register = registers.Register.cl }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = 6 }, result[1]);
}

test "decodeArguments - MOV Decode - Immediate to register narrow negative" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b11111010, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    // TODO next assertion could be wrong
    try std.testing.expectEqual(Operand{ .register = registers.Register.cl }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = -6 }, result[1]);
}

test "decodeArguments - MOV Decode - Immediate to register wide" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b10111001, 0b11111101, 0b11111111, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .register = registers.Register.cx }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = -3 }, result[1]);
}

test "decodeArguments - MOV Decode - Immediate to effective address, narrow" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b11000110, 0b11, 7, 0, 0, 0 },
        2,
    );
    std.debug.print("{}", .{subject.opcode.id});

    const result = try decodeArguments(subject);

    const expected_address = registers.EffectiveAddress{
        .r1 = registers.Register.bp,
        .r2 = registers.Register.di,
        .displacement = 0,
    };
    try std.testing.expectEqual(Operand{ .effective_address = expected_address }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = 7 }, result[1]);
}
