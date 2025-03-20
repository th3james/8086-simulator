const std = @import("std");

const instruction = @import("instruction.zig");
const instruction_layout = @import("instruction_layout.zig");
const opcodes = @import("opcodes.zig");
const registers = @import("register_names.zig");
const errors = @import("errors.zig");

const ImmediateSize = enum { registerDefined, byte, word };

const Immediate = struct {
    value: i16,
    size: ImmediateSize,
};

pub const Operand = union(enum) {
    register: registers.Register,
    absolute_address: u16,
    relative_address: i16,
    immediate: Immediate,
    effective_address: registers.EffectiveAddress,
    none,
};

pub fn decodeArguments(inst: instruction.Instruction) ![2]Operand {
    switch (inst.opcode.id) {
        .movRegOrMemToFromReg,
        .addRegOrMemToEither,
        .subRegOrMemToEither,
        .cmpRegOrMemToReg,
        => {
            const reg = registers.getRegister(
                inst.opcode.reg.?,
                inst.opcode.wide.?,
            );
            const opcode_mode = opcodes.Mode.fromInt(inst.opcode.mod.?);
            // Direct address exception
            if (opcode_mode == .memory_no_displacement and inst.opcode.regOrMem == 0b110) {
                return .{
                    Operand{ .register = reg },
                    Operand{ .absolute_address = @bitCast(try inst.getDisplacement()) },
                };
            }

            switch (opcode_mode) {
                .memory_no_displacement,
                .memory_8_bit_displacement,
                .memory_16_bit_displacement,
                => {
                    const displacement = if (opcode_mode == .memory_no_displacement)
                        0
                    else
                        try inst.getDisplacement();

                    const effective_address = registers.effectiveAddressRegisters(
                        inst.opcode.regOrMem.?,
                        displacement,
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
                .register => {
                    const regOrMem = registers.getRegister(inst.opcode.regOrMem.?, inst.opcode.wide.?);
                    if (inst.opcode.regIsDestination orelse false) {
                        return .{
                            Operand{ .register = reg },
                            Operand{ .register = regOrMem },
                        };
                    } else {
                        return .{
                            Operand{ .register = regOrMem },
                            Operand{ .register = reg },
                        };
                    }
                },
            }
        },

        .movImmediateToReg => {
            const reg = registers.getRegister(inst.opcode.reg.?, inst.opcode.wide.?);
            const immediate = try inst.getImmediate();
            return .{
                Operand{ .register = reg },
                Operand{ .immediate = .{ .value = immediate, .size = .registerDefined } },
            };
        },

        .movImmediateToRegOrMem,
        .addImmediateToRegOrMem,
        .subImmediateToRegOrMem,
        .cmpImmediateToRegOrMem,
        => {
            const immediate = try inst.getImmediate();

            const opcode_mode = opcodes.Mode.fromInt(inst.opcode.mod.?);
            // Direct address exception
            if (opcode_mode == .memory_no_displacement and inst.opcode.regOrMem == 0b110) {
                const size: ImmediateSize = if (inst.opcode.wide.?) .word else .byte;
                return .{
                    .{ .absolute_address = @bitCast(try inst.getDisplacement()) },
                    .{ .immediate = .{ .value = immediate, .size = size } },
                };
            }

            switch (opcode_mode) {
                .memory_no_displacement,
                .memory_8_bit_displacement,
                .memory_16_bit_displacement,
                => {
                    const effective_address = registers.effectiveAddressRegisters(
                        inst.opcode.regOrMem.?,
                        inst.getDisplacement() catch |err| switch (err) {
                            errors.InstructionErrors.NoDisplacement => 0,
                            else => {
                                return err;
                            },
                        },
                    );
                    const size: ImmediateSize = if (inst.opcode.wide.?) .word else .byte;
                    return .{
                        .{ .effective_address = effective_address },
                        .{ .immediate = .{ .value = immediate, .size = size } },
                    };
                },
                .register => {
                    const reg = registers.getRegister(inst.opcode.regOrMem.?, inst.opcode.wide.?);
                    return .{
                        .{ .register = reg },
                        .{ .immediate = .{ .value = immediate, .size = .registerDefined } },
                    };
                },
            }
        },

        .memoryToAccumulator => {
            const immediate = try inst.getImmediate();
            return .{
                .{ .register = .ax },
                .{ .effective_address = .{ .r1 = .none, .r2 = .none, .displacement = immediate } },
            };
        },

        .accumulatorToMemory => {
            const immediate = try inst.getImmediate();
            return .{
                .{ .effective_address = .{ .r1 = .none, .r2 = .none, .displacement = immediate } },
                .{ .register = .ax },
            };
        },

        .addImmediateToAccumulator,
        .subImmediateToAccumulator,
        .cmpImmediateWithAccumulator,
        => {
            const immediate_operand = Operand{
                .immediate = .{
                    .value = try inst.getImmediate(),
                    .size = .registerDefined,
                },
            };
            if (inst.opcode.wide.?) {
                return .{
                    .{ .register = .ax },
                    immediate_operand,
                };
            } else {
                return .{
                    .{ .register = .al },
                    immediate_operand,
                };
            }
        },

        .jmpIfZero,
        .jmpIfNotZero,
        .jmpIfLess,
        .jmpIfLessOrEq,
        .jmpIfBelow,
        .jmpIfBelowOrEq,
        .jmpIfParity,
        .jmpOnOverflow,
        .jmpOnSign,
        .jmpIfGreater,
        .jmpIfGreaterOrEq,
        .jmpIfAbove,
        .jmpIfAboveOrEq,
        .jmpIfParOdd,
        .jmpOnNotOverflow,
        .jmpOnNotSign,
        .loopCxTimes,
        .loopIfZero,
        .loopIfNotZero,
        .jmpIfCxZero,
        => {
            return .{
                Operand{ .relative_address = try inst.getDisplacement() },
                .none,
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
    try std.testing.expectEqual(Operand{ .absolute_address = 257 }, result[1]);
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
    try std.testing.expectEqual(Operand{ .immediate = .{ .value = 6, .size = .registerDefined } }, result[1]);
}

test "decodeArguments - MOV Decode - Immediate to register narrow negative" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b11111010, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    // TODO next assertion could be wrong
    try std.testing.expectEqual(Operand{ .register = registers.Register.cl }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = .{ .value = -6, .size = .registerDefined } }, result[1]);
}

test "decodeArguments - MOV Decode - Immediate to register wide" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b10111001, 0b11111101, 0b11111111, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .register = registers.Register.cx }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = .{ .value = -3, .size = .registerDefined } }, result[1]);
}

test "decodeArguments - MOV Decode - Immediate to effective address, narrow" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b11000110, 0b11, 7, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    const expected_address = registers.EffectiveAddress{
        .r1 = registers.Register.bp,
        .r2 = registers.Register.di,
        .displacement = 0,
    };
    try std.testing.expectEqual(Operand{ .effective_address = expected_address }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = .{ .value = 7, .size = .byte } }, result[1]);
}

test "decodeArguments - MOV Decode - Immediate to effective address, wide" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b11000111, 0b11, 8, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .immediate = .{ .value = 8, .size = .word } }, result[1]);
}

test "decodeArguments - MOV Decode - memory to accumulator narrow" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b1010_0000, 120, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .register = .ax }, result[0]);
    try std.testing.expectEqual(Operand{ .effective_address = .{
        .r1 = .none,
        .r2 = .none,
        .displacement = 120,
    } }, result[1]);
}

test "decodeArguments - MOV Decode - accumulator to memory, wide" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b1010_0011, 0b1000_0000, 0b0000_0001, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .effective_address = .{
        .r1 = .none,
        .r2 = .none,
        .displacement = 384,
    } }, result[0]);
    try std.testing.expectEqual(Operand{ .register = .ax }, result[1]);
}

// TODO - This is actually an integration test
test "decodeInstruction - ADD immediate to reg or mem" {
    const subject = try buildInstructionFromBytes(
        // Note: 4th byte should be ignored due to sign extension
        &[_]u8{ 0b1000_0011, 0b1100_0110, 0b0000_0010, 0b1000_0011, 0, 0 },
        2,
    );

    try std.testing.expectEqualStrings("add", subject.opcode.name);
    try std.testing.expectEqual(opcodes.OpcodeId.addImmediateToRegOrMem, subject.opcode.id);
    try std.testing.expectEqual(true, subject.opcode.sign);
    try std.testing.expectEqual(true, subject.opcode.wide);
    try std.testing.expectEqual(0b11, subject.opcode.mod);
    try std.testing.expectEqual(0b110, subject.opcode.regOrMem);

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .register = .si }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = .{ .value = 2, .size = .registerDefined } }, result[1]);
}

test "decodeArguments -  ADD immediate to accumulator narrow" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b0000_0100, 43, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .register = .al }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = .{ .value = 43, .size = .registerDefined } }, result[1]);
}

test "decodeArguments - ADD immediate to accumulator wide" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b0000_0101, 2, 1, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .register = .ax }, result[0]);
    try std.testing.expectEqual(Operand{ .immediate = .{ .value = 258, .size = .registerDefined } }, result[1]);
}

test "decodeArguments - JNZ" {
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b0111_0101, 34, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArguments(subject);

    try std.testing.expectEqual(Operand{ .relative_address = 34 }, result[0]);
    try std.testing.expectEqual(.none, result[1]);
}
