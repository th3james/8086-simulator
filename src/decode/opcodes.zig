const std = @import("std");
const assert = std.debug.assert;

pub const MAX_OPCODE_LENGTH = 2;

pub const OpcodeId = enum {
    movRegOrMemToFromReg,
    addRegOrMemToEither,
    subRegOrMemToEither,
    cmpRegOrMemToReg,
    movImmediateToReg,
    movImmediateToRegOrMem,
    addImmediateToRegOrMem,
    subImmediateToRegOrMem,
    cmpImmediateToRegOrMem,
    memoryToAccumulator,
    accumulatorToMemory,
    addImmediateToAccumulator,
    subImmediateToAccumulator,
    cmpImmediateWithAccumulator,
    jmpIfZero,
    jmpIfNotZero,
    jmpIfLess,
    jmpIfLessOrEq,
    jmpIfBelow,
    jmpIfBelowOrEq,
    jmpIfParity,
    jmpOnOverflow,
    jmpOnSign,
    jmpIfGreater,
    jmpIfGreaterOrEq,
    jmpIfAbove,
    jmpIfAboveOrEq,
    jmpIfParOdd,
    jmpOnNotOverflow,
    jmpOnNotSign,
    loopCxTimes,
    loopIfZero,
    loopIfNotZero,
    jmpIfCxZero,
};

pub const FieldDefinition = struct {
    mask: u16,
    shift: u4,
};

pub const OpcodeDefinition = struct {
    id: OpcodeId,
    name: []const u8,
    identifier_mask: u16,
    identifier: u16,
    bytes_required: u2,
    wide: ?FieldDefinition = null,
    sign: ?FieldDefinition = null,
    mod: ?FieldDefinition = null,
    reg: ?FieldDefinition = null,
    regOrMem: ?FieldDefinition = null,
    regIsDestination: ?FieldDefinition = null,
};

pub const DecodedOpcode = struct {
    id: OpcodeId,
    name: []const u8,
    length: u3,
    wide: ?bool = null,
    sign: bool = false,
    mod: ?u2 = null,
    reg: ?u3 = null,
    regOrMem: ?u3 = null,
    regIsDestination: ?bool = null,
};

pub const OpcodeTable = [_]OpcodeDefinition{
    .{
        .id = OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b1000_1000_0000_0000,
        .bytes_required = 2,
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.addRegOrMemToEither,
        .name = "add",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b0000_0000_0000_0000,
        .bytes_required = 2,
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.subRegOrMemToEither,
        .name = "sub",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b0010_1000_0000_0000,
        .bytes_required = 2,
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.cmpRegOrMemToReg,
        .name = "cmp",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b0011_1000_0000_0000,
        .bytes_required = 2,
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.movImmediateToRegOrMem,
        .name = "mov",
        .identifier_mask = 0b1111_1110_0011_1000,
        .identifier = 0b1100_0110_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.addImmediateToRegOrMem,
        .name = "add",
        .identifier_mask = 0b1111_1100_0011_1000,
        .identifier = 0b1000_0000_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
        .sign = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
    },
    .{
        .id = OpcodeId.subImmediateToRegOrMem,
        .name = "sub",
        .identifier_mask = 0b1111_1100_0011_1000,
        .identifier = 0b1000_0000_0010_1000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
        .sign = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
    },
    .{
        .id = OpcodeId.cmpImmediateToRegOrMem,
        .name = "cmp",
        .identifier_mask = 0b1111_1100_0011_1000,
        .identifier = 0b1000_0000_0011_1000,
        .bytes_required = 2,
        .sign = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.movImmediateToReg,
        .name = "mov",
        .identifier_mask = 0b1111_0000_0000_0000,
        .identifier = 0b1011_0000_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_1000_0000_0000, .shift = 11 },
        .reg = .{ .mask = 0b0000_0111_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.memoryToAccumulator,
        .name = "mov",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b1010_0000_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.accumulatorToMemory,
        .name = "mov",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b1010_0010_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.addImmediateToAccumulator,
        .name = "add",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b0000_0100_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.subImmediateToAccumulator,
        .name = "sub",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b0010_1100_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.cmpImmediateWithAccumulator,
        .name = "cmp",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b0011_1100_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.jmpIfZero,
        .name = "je",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0100_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfLess,
        .name = "jl",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1100_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfLessOrEq,
        .name = "jle",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1110_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfBelow,
        .name = "jb",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0010_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfBelowOrEq,
        .name = "jbe",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0110_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfNotZero,
        .name = "jnz",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0101_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfParity,
        .name = "jp",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1010_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpOnOverflow,
        .name = "jo",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0000_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpOnSign,
        .name = "js",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1000_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfGreater,
        .name = "jg",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1111_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfGreaterOrEq,
        .name = "jge",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1101_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfAbove,
        .name = "ja",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0111_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfAboveOrEq,
        .name = "jae",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0011_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfParOdd,
        .name = "jpo",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1011_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpOnNotOverflow,
        .name = "jno",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0001_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpOnNotSign,
        .name = "jns",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1001_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .loopCxTimes,
        .name = "loop",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b1110_0010_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .loopIfZero,
        .name = "loopz",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b1110_0001_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .loopIfNotZero,
        .name = "loopnz",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b1110_0000_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfCxZero,
        .name = "jcxz",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b1110_0011_0000_0000,
        .bytes_required = 1,
    },
};

pub const Mode = enum(u2) {
    memory_no_displacement = 0b00,
    memory_8_bit_displacement = 0b01,
    memory_16_bit_displacement = 0b10,
    register = 0b11,

    pub fn fromInt(value: u2) Mode {
        return @enumFromInt(value);
    }
};

// TODO this is inconsistent with errors.zig
pub const Errors = error{ InsufficientBytes, UnrecognisedOpcode };

pub fn decodeOpcode(bytes: []const u8) !DecodedOpcode {
    assert(bytes.len > 0);
    assert(bytes.len <= MAX_OPCODE_LENGTH);

    const identifier: u16 = switch (bytes.len) {
        1 => @as(u16, bytes[0]) << 8,
        2 => @as(u16, bytes[0]) << 8 | bytes[1],
        else => unreachable,
    };

    // TODO comptime loop?
    for (OpcodeTable) |mask| {
        if (mask.bytes_required > bytes.len) continue;

        if ((identifier & mask.identifier_mask) == mask.identifier) {
            var decoded_opcode = DecodedOpcode{
                .id = mask.id,
                .name = mask.name,
                .length = mask.bytes_required,
            };

            inline for (comptime std.meta.fieldNames(OpcodeDefinition)) |field| {
                const def = @field(mask, field);
                if (@TypeOf(def) == ?FieldDefinition) {
                    if (def) |field_def| {
                        const value = (identifier & field_def.mask) >> field_def.shift;
                        @field(decoded_opcode, field) = switch (@TypeOf(@field(decoded_opcode, field))) {
                            bool => value != 0,
                            ?bool => value != 0,
                            ?u2, ?u3 => @intCast(value),
                            else => @compileError("Unsupported field type for " ++ field),
                        };
                    }
                }
            }

            return decoded_opcode;
        }
    }
    return if (bytes.len == MAX_OPCODE_LENGTH)
        return Errors.UnrecognisedOpcode
    else
        return Errors.InsufficientBytes;
}

test "decodeOpcode - Unknown opcode with one byte returns InsufficientBytes error" {
    const result = decodeOpcode(&[_]u8{0});
    try std.testing.expectError(Errors.InsufficientBytes, result);
}

test "decodeOpcode - Unknown opcode with max byte returns UnrecognisedOpcode error" {
    const result = decodeOpcode(&[_]u8{ 0b11111111, 0b11 });
    try std.testing.expectError(Errors.UnrecognisedOpcode, result);
}

test "decodeOpcode - MOV Memory mode, no displacement" {
    const result = try decodeOpcode(&[_]u8{ 0b1000_1000, 0b0000_0000 });
    try std.testing.expectEqual(OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(2, result.length);
    try std.testing.expectEqual(false, result.wide.?);
    try std.testing.expectEqual(0b00, result.mod.?);
    try std.testing.expectEqual(0b000, result.reg.?);
    try std.testing.expectEqual(0b000, result.regOrMem.?);
}

test "decodeOpcode - MOV Memory mode, direct address" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b00000110 });
    try std.testing.expectEqual(OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}

test "decodeOpcode - Reg-to-reg MOV Decode" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b11000000 });
    try std.testing.expectEqual(OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}

test "decodeOpcode - MOV Decode Memory mode 8-bit" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b01000000 });
    try std.testing.expectEqual(OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(Mode.memory_8_bit_displacement, Mode.fromInt(result.mod.?));
}

test "decodeOpcode - MOV Decode Memory mode 16-bit" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b10000000 });
    try std.testing.expectEqual(OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}

test "decodeOpcode - MOV Immediate to register narrow" {
    const result = try decodeOpcode(&[_]u8{ 0b10110001, 0b00000000 });
    try std.testing.expectEqual(OpcodeId.movImmediateToReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(false, result.wide.?);
    try std.testing.expectEqual(0b001, result.reg.?);
}

test "decodeOpcode - MOV Immediate to register wide" {
    const result = try decodeOpcode(&[_]u8{ 0b10111000, 0b00000000 });
    try std.testing.expectEqual(OpcodeId.movImmediateToReg, result.id);
    try std.testing.expectEqual(true, result.wide.?);
}
