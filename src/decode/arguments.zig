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
    relative_address: i16,
    immediate: Immediate, // TODO might need an unsigned variant?
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
                Operand{ .immediate = .{ .value = immediate, .size = .registerDefined } },
            };
        },

        opcodes.OpcodeId.movImmediateToRegOrMem,
        opcodes.OpcodeId.addImmediateToRegOrMem,
        opcodes.OpcodeId.subImmediateToRegOrMem,
        opcodes.OpcodeId.cmpImmediateToRegOrMem,
        => {
            switch (opcodes.Mode.fromInt(inst.opcode.mod.?)) {
                .memory_no_displacement => {
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
                    const size: ImmediateSize = if (inst.opcode.wide.?) .word else .byte;
                    return .{
                        .{ .effective_address = effective_address },
                        .{ .immediate = .{ .value = immediate, .size = size } },
                    };
                },
                else => {
                    std.debug.panic("Unsupported mod: {}", .{opcodes.Mode.fromInt(inst.opcode.mod.?)});
                },
            }
        },

        opcodes.OpcodeId.memoryToAccumulator => {
            const immediate = try inst.getImmediate();
            return .{
                .{ .register = .ax },
                .{ .effective_address = .{ .r1 = .none, .r2 = .none, .displacement = immediate } },
            };
        },

        opcodes.OpcodeId.accumulatorToMemory => {
            const immediate = try inst.getImmediate();
            return .{
                .{ .effective_address = .{ .r1 = .none, .r2 = .none, .displacement = immediate } },
                .{ .register = .ax },
            };
        },

        else => {
            std.debug.print("Got unimplemented opcode {}\n", .{inst.opcode.id});
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
    try std.testing.expectEqual(Operand{ .effective_address = .{
        .r1 = .none,
        .r2 = .none,
        .displacement = 2,
    } }, result[1]);
}
