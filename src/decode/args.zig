const std = @import("std");
const assert = std.debug.assert;

const opcodes = @import("opcodes.zig");
const instruction_layout = @import("instruction_layout.zig");
const instruction = @import("instruction.zig");
const register_names = @import("register_names.zig");
const errors = @import("errors.zig");

const InstructionArgs = struct {
    args: []const []const u8,

    pub fn deinit(self: *const InstructionArgs, allocator: std.mem.Allocator) void {
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
    }
};

pub fn decodeArgs(allocator: std.mem.Allocator, raw: instruction.Instruction) !InstructionArgs {
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    switch (raw.opcode.id) {
        opcodes.OpcodeId.movRegOrMemToFromReg,
        opcodes.OpcodeId.addRegOrMemToEither,
        opcodes.OpcodeId.subRegOrMemToEither,
        opcodes.OpcodeId.cmpRegOrMemToReg,
        => {
            // TODO improve optional unwraps
            switch (raw.opcode.mod.?) {
                0b00 => { // Memory mode, no displacement
                    if (raw.opcode.regOrMem == 0b110) { // Direct address
                        try args.append(try allocator.dupe(u8, register_names.registerName(raw.opcode.reg.?, raw.opcode.wide.?)));
                        const memory_address = try raw.getDisplacement();
                        const memory_address_str = try std.fmt.allocPrint(allocator, "[{}]", .{memory_address});
                        try args.append(memory_address_str);
                    } else {
                        try appendEffectiveAddress(
                            allocator,
                            &args,
                            raw.opcode,
                            0,
                        );
                    }
                },
                0b11 => { // Register to Register
                    const regName = register_names.registerName(raw.opcode.reg.?, raw.opcode.wide.?);
                    const regOrMemName = register_names.registerName(raw.opcode.regOrMem.?, raw.opcode.wide.?);
                    if (raw.opcode.regIsDestination orelse false) {
                        try args.append(try allocator.dupe(u8, regName));
                        try args.append(try allocator.dupe(u8, regOrMemName));
                    } else {
                        try args.append(try allocator.dupe(u8, regOrMemName));
                        try args.append(try allocator.dupe(u8, regName));
                    }
                },
                else => {
                    try appendEffectiveAddress(
                        allocator,
                        &args,
                        raw.opcode,
                        try raw.getDisplacement(),
                    );
                },
            }
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.movImmediateToRegOrMem,
        opcodes.OpcodeId.addImmediateToRegOrMem,
        opcodes.OpcodeId.subImmediateToRegOrMem,
        opcodes.OpcodeId.cmpImmediateToRegOrMem,
        => {
            switch (raw.opcode.mod.?) {
                0b00 => { // Memory mode, no displacement
                    if (raw.opcode.regOrMem == 0b110) { // Direct address
                        const memory_address = try raw.getDisplacement();
                        const memory_address_str = try std.fmt.allocPrint(allocator, "[{}]", .{memory_address});
                        try args.append(memory_address_str);
                    } else {
                        const effectiveAddress = register_names.effectiveAddressRegisters(raw.opcode.regOrMem.?, // TODO can this unwrap be avoided?
                            raw.getDisplacement() catch |err| switch (err) {
                            errors.InstructionErrors.NoDisplacement => 0,
                            else => {
                                return err;
                            },
                        });
                        try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
                    }
                    const immediate = try raw.getImmediate();
                    const immediate_size = if (raw.opcode.wide.?)
                        "word"
                    else
                        "byte";
                    const immediate_str = try std.fmt.allocPrint(allocator, "{s} {}", .{
                        immediate_size,
                        immediate,
                    });
                    try args.append(immediate_str);
                },
                0b11 => { // Register to Register
                    const regOrMemName = register_names.registerName(raw.opcode.regOrMem.?, raw.opcode.wide.?);
                    try args.append(try allocator.dupe(u8, regOrMemName));
                    const immediate = try raw.getImmediate();
                    const immediate_str = try std.fmt.allocPrint(allocator, "{}", .{
                        immediate,
                    });
                    try args.append(immediate_str);
                },
                else => {
                    const effectiveAddress = register_names.effectiveAddressRegisters(raw.opcode.regOrMem.?, // TODO can this unwrap be avoided?
                        raw.getDisplacement() catch |err| switch (err) {
                        errors.InstructionErrors.NoDisplacement => 0,
                        else => {
                            return err;
                        },
                    });
                    try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
                    const immediate = try raw.getImmediate();
                    const immediate_size = if (raw.opcode.wide.?)
                        "word"
                    else
                        "byte";
                    const immediate_str = try std.fmt.allocPrint(allocator, "{s} {}", .{
                        immediate_size,
                        immediate,
                    });
                    try args.append(immediate_str);
                },
            }
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.movImmediateToReg => {
            try args.append(try allocator.dupe(u8, register_names.registerName(raw.opcode.reg.?, raw.opcode.wide.?)));

            if (raw.opcode.wide.?) {
                const data_signed = try raw.getImmediate();
                const data: i16 = @bitCast(data_signed);
                const data_str = try std.fmt.allocPrint(allocator, "{d}", .{data});
                try args.append(data_str);
            } else {
                const data: i8 = @bitCast(raw.base[1]);
                const data_str = try std.fmt.allocPrint(allocator, "{d}", .{data});
                try args.append(data_str);
            }
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.memoryToAccumulator => {
            // TODO handle wide
            try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "[{d}]", .{
                try raw.getImmediate(),
            }));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.accumulatorToMemory => {
            try args.append(try std.fmt.allocPrint(allocator, "[{d}]", .{
                try raw.getImmediate(),
            }));
            // TODO handle wide
            try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.addImmediateToAccumulator,
        opcodes.OpcodeId.subImmediateToAccumulator,
        opcodes.OpcodeId.cmpImmediateWithAccumulator,
        => {
            if (raw.opcode.wide.?) {
                try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            } else {
                try args.append(try std.fmt.allocPrint(allocator, "al", .{}));
            }
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{
                try raw.getImmediate(),
            }));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
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
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{
                try raw.getDisplacement(),
            }));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },
    }
}

fn appendEffectiveAddress(
    allocator: std.mem.Allocator,
    args: *std.ArrayList([]const u8),
    opcode: opcodes.DecodedOpcode,
    displacement: i16,
) !void {
    const effectiveAddress = register_names.effectiveAddressRegisters(
        opcode.regOrMem.?, // TODO can this unwrap be avoided?
        displacement,
    );
    if (opcode.regIsDestination orelse false) {
        try args.append(try allocator.dupe(
            u8,
            register_names.registerName(opcode.reg.?, opcode.wide.?),
        ));
        try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
    } else {
        try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
        try args.append(try allocator.dupe(
            u8,
            register_names.registerName(opcode.reg.?, opcode.wide.?),
        ));
    }
}

fn buildInstructionFromBytes(bytes: []const u8, length: u4) !instruction.Instruction {
    const result = try opcodes.decodeOpcode(bytes[0..length]);
    return instruction.Instruction{
        .base = bytes[0..],
        .opcode = result,
        .layout = instruction_layout.getInstructionLayout(result),
    };
}

test "decodeArgs - MOV Decode - Reg to Reg" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0b10001000, 0b11000001, 0, 0, 0, 0 };
    // TODO this the_... naming is horrid
    const the_raw_instruction = try buildInstructionFromBytes(
        &bytes,
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("cl", result.args[0]);
    try std.testing.expectEqualStrings("al", result.args[1]);
}

test "decodeArgs - MOV Direct address" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b10001000, 0b00000110, 0b1, 0b1, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("al", result.args[0]);
    try std.testing.expectEqualStrings("[257]", result.args[1]);
}

test "decodeArgs - MOV reg or memory" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b1000_1011, 0b0100_0001, 0b1101_1011, 0b0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("ax", result.args[0]);
    try std.testing.expectEqualStrings("[bx + di - 37]", result.args[1]);
}

test "decodeArgs - MOV Decode - Immediate to register narrow positive" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b00000110, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register narrow positive" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b00000110, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register narrow negative" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b11111010, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("-6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register wide" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b10111001, 0b11111101, 0b11111111, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, true), result.args[0]);
    try std.testing.expectEqualStrings("-3", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register or memory - byte" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b11000110, 0b11, 7, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("[bp + di]", result.args[0]);
    try std.testing.expectEqualStrings("byte 7", result.args[1]);
}

test "decodeInstruction - MOV Decode - memory to accumulator narrow" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b1010_0000, 120, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("ax", result.args[0]);
    try std.testing.expectEqualStrings("[120]", result.args[1]);
}

test "decodeInstruction - MOV Decode - accumulator to memory wide" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b1010_0011, 0b1000_0000, 0b0000_0001, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("[384]", result.args[0]);
    try std.testing.expectEqualStrings("ax", result.args[1]);
}

// TODO - This is actually an integration test
test "decodeInstruction - ADD immediate to reg or mem" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        // Note: 4th byte should be ignored due to sign extension
        &[_]u8{ 0b1000_0011, 0b1100_0110, 0b0000_0010, 0b1000_0011, 0, 0 },
        2,
    );

    try std.testing.expectEqualStrings("add", the_raw_instruction.opcode.name);
    try std.testing.expectEqual(opcodes.OpcodeId.addImmediateToRegOrMem, the_raw_instruction.opcode.id);
    try std.testing.expectEqual(true, the_raw_instruction.opcode.sign);
    try std.testing.expectEqual(true, the_raw_instruction.opcode.wide);
    try std.testing.expectEqual(0b11, the_raw_instruction.opcode.mod);
    try std.testing.expectEqual(0b110, the_raw_instruction.opcode.regOrMem);

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("si", result.args[0]);
    try std.testing.expectEqualStrings("2", result.args[1]);
}

test "decodeInstruction - JNZ" {
    const allocator = std.testing.allocator;
    const the_raw_instruction = try buildInstructionFromBytes(
        &[_]u8{ 0b1010_0011, 0b1000_0000, 0b0000_0001, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, the_raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("[384]", result.args[0]);
    try std.testing.expectEqualStrings("ax", result.args[1]);
}
