const std = @import("std");
const assert = std.debug.assert;
const opcodes = @import("opcodes.zig");

pub const MAX_INSTRUCTION_LENGTH = 6;

pub const InstructionField = struct {
    start: u4,
    end: u4,
};

pub const InstructionLayout = struct {
    displacement: ?InstructionField = null,
    data: ?InstructionField = null,
};

pub fn getInstructionLayout(decoded_opcode: opcodes.DecodedOpcode) InstructionLayout {
    var result = InstructionLayout{};
    switch (decoded_opcode.id) {
        .movRegOrMemToFromReg,
        .addRegOrMemToEither,
        .subRegOrMemToEither,
        .cmpRegOrMemToReg,
        => {
            if (decoded_opcode.mod) |mod| {
                result.displacement = switch (mod) {
                    0b00 => if (decoded_opcode.regOrMem == 0b110)
                        .{ .start = 2, .end = 4 }
                    else
                        null,
                    0b01 => .{ .start = 2, .end = 3 },
                    0b10 => .{ .start = 2, .end = 4 },
                    else => null,
                };
            }
        },
        .movImmediateToReg,
        .accumulatorToMemory,
        .memoryToAccumulator,
        .addImmediateToAccumulator,
        .subImmediateToAccumulator,
        .cmpImmediateWithAccumulator,
        => {
            result.data = .{
                .start = 1,
                .end = if (decoded_opcode.wide.?)
                    3
                else
                    2,
            };
        },
        .movImmediateToRegOrMem,
        .addImmediateToRegOrMem,
        .subImmediateToRegOrMem,
        .cmpImmediateToRegOrMem,
        => {
            if (decoded_opcode.mod) |mod| {
                result.displacement = switch (mod) {
                    0b00 => if (decoded_opcode.regOrMem == 0b110)
                        .{ .start = 2, .end = 4 }
                    else
                        null,
                    0b01 => .{ .start = 2, .end = 3 },
                    0b10 => .{ .start = 2, .end = 4 },
                    else => null,
                };
            }

            const next = if (result.displacement) |displacement|
                displacement.end
            else
                2;

            result.data = .{
                .start = next,
                .end = if (decoded_opcode.wide.? and !decoded_opcode.sign)
                    next + 2
                else
                    next + 1,
            };
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
            result.displacement = .{
                .start = 1,
                .end = 2,
            };
        },
    }
    return result;
}

test "getInstructionDataMap - MOV Memory mode, no displacement" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .regOrMem = 0b000,
        .length = 2,
    };
    const result = getInstructionLayout(decoded_opcode);
    try std.testing.expectEqual(null, result.displacement);
}

test "getInstructionDataMap - MOV Memory mode, direct address" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b00,
        .regOrMem = 0b110,
        .length = 2,
    };
    const result = getInstructionLayout(decoded_opcode);
    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(4, result.displacement.?.end);
}

test "getInstructionDataMap - Reg-to-reg MOV Decode" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b11,
        .regOrMem = 0b110,
        .length = 2,
    };
    const result = getInstructionLayout(decoded_opcode);
    try std.testing.expectEqual(null, result.displacement);
}

test "getInstructionDataMap - MOV Decode Memory mode 8-bit" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b01,
        .regOrMem = 0b000,
        .length = 2,
    };
    const result = getInstructionLayout(decoded_opcode);
    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(3, result.displacement.?.end);
}

test "getInstructionDataMap - MOV Decode Memory mode 16-bit" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b10,
        .length = 2,
    };
    const result = getInstructionLayout(decoded_opcode);
    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(4, result.displacement.?.end);
}

test "getInstructionDataMap - MOV Immediate to register narrow" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movImmediateToReg,
        .name = "mov",
        .wide = false,
        .length = 1,
    };
    const result = getInstructionLayout(decoded_opcode);
    try std.testing.expectEqual(1, result.data.?.start);
    try std.testing.expectEqual(2, result.data.?.end);
}

test "getInstructionDataMap - MOV Immediate to register wide" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movImmediateToReg,
        .name = "mov",
        .wide = true,
        .length = 1,
    };
    const result = getInstructionLayout(decoded_opcode);
    try std.testing.expectEqual(1, result.data.?.start);
    try std.testing.expectEqual(3, result.data.?.end);
}

test "getInstructionDataMap - MOV Immediate to register/memory, wide displacement, narrow data" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movImmediateToRegOrMem,
        .name = "mov",
        .wide = false,
        .mod = 0b10,
        .length = 2,
    };

    const result = getInstructionLayout(decoded_opcode);

    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(4, result.displacement.?.end);
    try std.testing.expectEqual(4, result.data.?.start);
    try std.testing.expectEqual(5, result.data.?.end);
}

test "getInstructionDataMap - MOV Immediate to register/memory wide, no displacement, wide data" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.movImmediateToRegOrMem,
        .name = "mov",
        .wide = true,
        .mod = 0b00,
        .length = 2,
    };

    const result = getInstructionLayout(decoded_opcode);

    try std.testing.expectEqual(null, result.displacement);
    try std.testing.expectEqual(2, result.data.?.start);
    try std.testing.expectEqual(4, result.data.?.end);
}

test "getInstructionDataMap - ADD immediate to reg or mem with wide sign extension" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.addImmediateToRegOrMem,
        .name = "mov",
        .sign = true,
        .wide = true,
        .length = 2,
    };

    const result = getInstructionLayout(decoded_opcode);

    try std.testing.expectEqual(null, result.displacement);
    try std.testing.expectEqual(2, result.data.?.start);
    try std.testing.expectEqual(3, result.data.?.end);
}

test "getInstructionDataMap - JNZ has signed displacement" {
    const decoded_opcode = opcodes.DecodedOpcode{
        .id = opcodes.OpcodeId.jmpIfNotZero,
        .name = "jnz",
        .length = 1,
    };

    const result = getInstructionLayout(decoded_opcode);

    try std.testing.expectEqual(null, result.data);
    try std.testing.expectEqual(1, result.displacement.?.start);
    try std.testing.expectEqual(2, result.displacement.?.end);
}

pub fn getInstructionLength(opcode_len: u4, data_map: InstructionLayout) u4 {
    assert(opcode_len > 0);
    var length = opcode_len;

    inline for (std.meta.fields(InstructionLayout)) |field| {
        if (@field(data_map, field.name)) |value| {
            if (@hasField(@TypeOf(value), "end")) {
                length = @max(length, value.end);
            }
        }
    }

    assert(length >= opcode_len);
    assert(length <= MAX_INSTRUCTION_LENGTH);
    return length;
}

test "getInstructionLength - returns opcode length when there is no additional data" {
    const in = InstructionLayout{};
    try std.testing.expectEqual(2, getInstructionLength(2, in));
}

test "getInstructionLength - returns the end of displacement when specified" {
    const in = InstructionLayout{ .displacement = .{
        .start = 2,
        .end = 3,
    } };
    try std.testing.expectEqual(3, getInstructionLength(2, in));
}

test "getInstructionLength - returns the end of data when specified" {
    const in = InstructionLayout{ .data = .{
        .start = 1,
        .end = 2,
    } };
    try std.testing.expectEqual(2, getInstructionLength(1, in));
}

test "getInstructionLength - returns the maximum end value when multiple fields are specified" {
    const in = InstructionLayout{
        .displacement = .{
            .start = 1,
            .end = 3,
        },
        .data = .{
            .start = 1,
            .end = 2,
        },
    };
    try std.testing.expectEqual(3, getInstructionLength(1, in));
}
