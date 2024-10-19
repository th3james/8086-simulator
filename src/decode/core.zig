const std = @import("std");
const assert = std.debug.assert;
const opcode_masks = @import("opcode_masks.zig");
const register_names = @import("register_names.zig");

pub const MAX_OPCODE_LENGTH = 2;
pub const MAX_INSTRUCTION_LENGTH = 6;

pub const InstructionErrors = error{ UnhandledRange, NoDisplacement, NoData };
pub const RawInstruction = struct {
    base: []const u8,
    opcode: opcode_masks.DecodedOpcode,
    data_map: opcode_masks.InstructionDataMap,

    fn extractValue(self: *const RawInstruction, field: opcode_masks.InstructionField) InstructionErrors!i16 {
        if (field.end - field.start == 1) {
            return @as(i16, @as(i8, @bitCast(self.base[field.start])));
        } else if (field.end - field.start == 2) {
            return @as(i16, @bitCast(@as(u16, self.base[field.end - 1]) << 8 | @as(u16, self.base[field.start])));
        } else {
            return InstructionErrors.UnhandledRange;
        }
    }

    pub fn getDisplacement(self: *const RawInstruction) InstructionErrors!i16 {
        const displacement_map = self.data_map.displacement orelse return InstructionErrors.NoDisplacement;
        return self.extractValue(displacement_map);
    }

    pub fn getData(self: *const RawInstruction) InstructionErrors!i16 {
        const data_map = self.data_map.data orelse return InstructionErrors.NoData;
        return self.extractValue(data_map);
    }
};

test "RawInstruction.getDisplacement - errors when no data map" {
    var base = [_]u8{ 0b10111001, 0b10, 0b1, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 1 },
        .data_map = .{},
    };
    try std.testing.expectError(InstructionErrors.NoDisplacement, in.getDisplacement());
}

test "RawInstruction.getDisplacement - positive narrow" {
    var base = [_]u8{ 0b10111001, 1, 0, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 1 },
        .data_map = .{
            .displacement = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(1, try in.getDisplacement());
}

test "RawInstruction.getDisplacement - negative narrow is sign-extended" {
    var base = [_]u8{ 0b10111001, 0b1101_1011, 0, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{
            .displacement = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(-37, try in.getDisplacement());
}

test "RawInstruction.getDisplacement - wide" {
    var base = [_]u8{ 0b10111001, 0, 0b1, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{
            .displacement = .{
                .start = 1,
                .end = 3,
            },
        },
    };
    try std.testing.expectEqual(256, try in.getDisplacement());
}

test "RawInstruction.getData - errors when no data map" {
    var base = [_]u8{ 0b10111001, 0b10, 0b1, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{},
    };
    try std.testing.expectError(InstructionErrors.NoData, in.getData());
}

test "RawInstruction.getData - narrow" {
    var base = [_]u8{ 0b10111001, 0b10, 0, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{
            .data = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(2, try in.getData());
}

const InstructionArgs = struct {
    args: []const []const u8,

    pub fn deinit(self: *const InstructionArgs, allocator: std.mem.Allocator) void {
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
    }
};

pub const Errors = error{ InsufficientBytes, UnrecognisedOpcode };

pub fn decodeOpcode(bytes: []const u8) !opcode_masks.DecodedOpcode {
    assert(bytes.len > 0);
    assert(bytes.len <= MAX_OPCODE_LENGTH);

    const identifier: u16 = switch (bytes.len) {
        1 => @as(u16, bytes[0]) << 8,
        2 => @as(u16, bytes[0]) << 8 | bytes[1],
        else => unreachable,
    };

    // TODO comptime loop?
    for (opcode_masks.OpcodeTable) |mask| {
        if (mask.bytes_required > bytes.len) continue;

        if ((identifier & mask.identifier_mask) == mask.identifier) {
            var decoded_opcode = opcode_masks.DecodedOpcode{
                .id = mask.id,
                .name = mask.name,
                .length = mask.bytes_required,
            };

            inline for (comptime std.meta.fieldNames(opcode_masks.OpcodeDefinition)) |field| {
                const def = @field(mask, field);
                if (@TypeOf(def) == ?opcode_masks.FieldDefinition) {
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
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(2, result.length);
    try std.testing.expectEqual(false, result.wide.?);
    try std.testing.expectEqual(0b00, result.mod.?);
    try std.testing.expectEqual(0b000, result.reg.?);
    try std.testing.expectEqual(0b000, result.regOrMem.?);
}

test "decodeOpcode - MOV Memory mode, direct address" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b00000110 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}

test "decodeOpcode - Reg-to-reg MOV Decode" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b11000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}

test "decodeOpcode - MOV Decode Memory mode 8-bit" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b01000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(0b01, result.mod.?);
}

test "decodeOpcode - MOV Decode Memory mode 16-bit" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b10000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}

test "decodeOpcode - MOV Immediate to register narrow" {
    const result = try decodeOpcode(&[_]u8{ 0b10110001, 0b00000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movImmediateToReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(false, result.wide.?);
    try std.testing.expectEqual(0b001, result.reg.?);
}

test "decodeOpcode - MOV Immediate to register wide" {
    const result = try decodeOpcode(&[_]u8{ 0b10111000, 0b00000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movImmediateToReg, result.id);
    try std.testing.expectEqual(true, result.wide.?);
}

pub fn getInstructionDataMap(decoded_opcode: opcode_masks.DecodedOpcode) opcode_masks.InstructionDataMap {
    var result = opcode_masks.InstructionDataMap{};
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
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .regOrMem = 0b000,
        .length = 2,
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(null, result.displacement);
}

test "getInstructionDataMap - MOV Memory mode, direct address" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b00,
        .regOrMem = 0b110,
        .length = 2,
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(4, result.displacement.?.end);
}

test "getInstructionDataMap - Reg-to-reg MOV Decode" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b11,
        .regOrMem = 0b110,
        .length = 2,
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(null, result.displacement);
}

test "getInstructionDataMap - MOV Decode Memory mode 8-bit" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b01,
        .regOrMem = 0b000,
        .length = 2,
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(3, result.displacement.?.end);
}

test "getInstructionDataMap - MOV Decode Memory mode 16-bit" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .mod = 0b10,
        .length = 2,
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(4, result.displacement.?.end);
}

test "getInstructionDataMap - MOV Immediate to register narrow" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movImmediateToReg,
        .name = "mov",
        .wide = false,
        .length = 1,
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(1, result.data.?.start);
    try std.testing.expectEqual(2, result.data.?.end);
}

test "getInstructionDataMap - MOV Immediate to register wide" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movImmediateToReg,
        .name = "mov",
        .wide = true,
        .length = 1,
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(1, result.data.?.start);
    try std.testing.expectEqual(3, result.data.?.end);
}

test "getInstructionDataMap - MOV Immediate to register/memory, wide displacement, narrow data" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movImmediateToRegOrMem,
        .name = "mov",
        .wide = false,
        .mod = 0b10,
        .length = 2,
    };

    const result = getInstructionDataMap(decoded_opcode);

    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(4, result.displacement.?.end);
    try std.testing.expectEqual(4, result.data.?.start);
    try std.testing.expectEqual(5, result.data.?.end);
}

test "getInstructionDataMap - MOV Immediate to register/memory wide, no displacement, wide data" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movImmediateToRegOrMem,
        .name = "mov",
        .wide = true,
        .mod = 0b00,
        .length = 2,
    };

    const result = getInstructionDataMap(decoded_opcode);

    try std.testing.expectEqual(null, result.displacement);
    try std.testing.expectEqual(2, result.data.?.start);
    try std.testing.expectEqual(4, result.data.?.end);
}

test "getInstructionDataMap - ADD immediate to reg or mem with wide sign extension" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.addImmediateToRegOrMem,
        .name = "mov",
        .sign = true,
        .wide = true,
        .length = 2,
    };

    const result = getInstructionDataMap(decoded_opcode);

    try std.testing.expectEqual(null, result.displacement);
    try std.testing.expectEqual(2, result.data.?.start);
    try std.testing.expectEqual(3, result.data.?.end);
}

test "getInstructionDataMap - JNZ has signed displacement" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.jmpIfNotZero,
        .name = "jnz",
        .length = 1,
    };

    const result = getInstructionDataMap(decoded_opcode);

    try std.testing.expectEqual(null, result.data);
    try std.testing.expectEqual(1, result.displacement.?.start);
    try std.testing.expectEqual(2, result.displacement.?.end);
}

pub fn getInstructionLength(opcode_len: u4, data_map: opcode_masks.InstructionDataMap) u4 {
    assert(opcode_len > 0);
    var length = opcode_len;

    inline for (std.meta.fields(opcode_masks.InstructionDataMap)) |field| {
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
    const in = opcode_masks.InstructionDataMap{};
    try std.testing.expectEqual(2, getInstructionLength(2, in));
}

test "getInstructionLength - returns the end of displacement when specified" {
    const in = opcode_masks.InstructionDataMap{ .displacement = .{
        .start = 2,
        .end = 3,
    } };
    try std.testing.expectEqual(3, getInstructionLength(2, in));
}

test "getInstructionLength - returns the end of data when specified" {
    const in = opcode_masks.InstructionDataMap{ .data = .{
        .start = 1,
        .end = 2,
    } };
    try std.testing.expectEqual(2, getInstructionLength(1, in));
}

test "getInstructionLength - returns the maximum end value when multiple fields are specified" {
    const in = opcode_masks.InstructionDataMap{
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

pub fn decodeArgs(allocator: std.mem.Allocator, raw: RawInstruction) !InstructionArgs {
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    switch (raw.opcode.id) {
        opcode_masks.OpcodeId.movRegOrMemToFromReg,
        opcode_masks.OpcodeId.addRegOrMemToEither,
        opcode_masks.OpcodeId.subRegOrMemToEither,
        opcode_masks.OpcodeId.cmpRegOrMemToReg,
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

        opcode_masks.OpcodeId.movImmediateToRegOrMem,
        opcode_masks.OpcodeId.addImmediateToRegOrMem,
        opcode_masks.OpcodeId.subImmediateToRegOrMem,
        opcode_masks.OpcodeId.cmpImmediateToRegOrMem,
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
                            InstructionErrors.NoDisplacement => 0,
                            else => {
                                return err;
                            },
                        });
                        try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
                    }
                    const immediate = try raw.getData();
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
                    const immediate = try raw.getData();
                    const immediate_str = try std.fmt.allocPrint(allocator, "{}", .{
                        immediate,
                    });
                    try args.append(immediate_str);
                },
                else => {
                    const effectiveAddress = register_names.effectiveAddressRegisters(raw.opcode.regOrMem.?, // TODO can this unwrap be avoided?
                        raw.getDisplacement() catch |err| switch (err) {
                        InstructionErrors.NoDisplacement => 0,
                        else => {
                            return err;
                        },
                    });
                    try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
                    const immediate = try raw.getData();
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

        opcode_masks.OpcodeId.movImmediateToReg => {
            try args.append(try allocator.dupe(u8, register_names.registerName(raw.opcode.reg.?, raw.opcode.wide.?)));

            if (raw.opcode.wide.?) {
                const data_signed = try raw.getData();
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

        opcode_masks.OpcodeId.memoryToAccumulator => {
            // TODO handle wide
            try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "[{d}]", .{
                try raw.getData(),
            }));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcode_masks.OpcodeId.accumulatorToMemory => {
            try args.append(try std.fmt.allocPrint(allocator, "[{d}]", .{
                try raw.getData(),
            }));
            // TODO handle wide
            try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcode_masks.OpcodeId.addImmediateToAccumulator,
        opcode_masks.OpcodeId.subImmediateToAccumulator,
        opcode_masks.OpcodeId.cmpImmediateWithAccumulator,
        => {
            if (raw.opcode.wide.?) {
                try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            } else {
                try args.append(try std.fmt.allocPrint(allocator, "al", .{}));
            }
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{
                try raw.getData(),
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
    opcode: opcode_masks.DecodedOpcode,
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

fn buildRawInstructionFromBytes(bytes: []const u8, length: u4) !RawInstruction {
    const opcode = try decodeOpcode(bytes[0..length]);
    return RawInstruction{
        .base = bytes[0..],
        .opcode = opcode,
        .data_map = getInstructionDataMap(opcode),
    };
}

test "decodeArgs - MOV Decode - Reg to Reg" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0b10001000, 0b11000001, 0, 0, 0, 0 };
    const raw_instruction = try buildRawInstructionFromBytes(
        &bytes,
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("cl", result.args[0]);
    try std.testing.expectEqualStrings("al", result.args[1]);
}

test "decodeArgs - MOV Direct address" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b10001000, 0b00000110, 0b1, 0b1, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("al", result.args[0]);
    try std.testing.expectEqualStrings("[257]", result.args[1]);
}

test "decodeArgs - MOV reg or memory" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b1000_1011, 0b0100_0001, 0b1101_1011, 0b0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("ax", result.args[0]);
    try std.testing.expectEqualStrings("[bx + di - 37]", result.args[1]);
}

test "decodeArgs - MOV Decode - Immediate to register narrow positive" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b00000110, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register narrow positive" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b00000110, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register narrow negative" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b10110001, 0b11111010, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("-6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register wide" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b10111001, 0b11111101, 0b11111111, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(register_names.registerName(0b1, true), result.args[0]);
    try std.testing.expectEqualStrings("-3", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register or memory - byte" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b11000110, 0b11, 7, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("[bp + di]", result.args[0]);
    try std.testing.expectEqualStrings("byte 7", result.args[1]);
}

test "decodeInstruction - MOV Decode - memory to accumulator narrow" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b1010_0000, 120, 0, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("ax", result.args[0]);
    try std.testing.expectEqualStrings("[120]", result.args[1]);
}

test "decodeInstruction - MOV Decode - accumulator to memory wide" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b1010_0011, 0b1000_0000, 0b0000_0001, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("[384]", result.args[0]);
    try std.testing.expectEqualStrings("ax", result.args[1]);
}

// TODO - This is actually an integration test
test "decodeInstruction - ADD immediate to reg or mem" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        // Note: 4th byte should be ignored due to sign extension
        &[_]u8{ 0b1000_0011, 0b1100_0110, 0b0000_0010, 0b1000_0011, 0, 0 },
        2,
    );

    try std.testing.expectEqualStrings("add", raw_instruction.opcode.name);
    try std.testing.expectEqual(opcode_masks.OpcodeId.addImmediateToRegOrMem, raw_instruction.opcode.id);
    try std.testing.expectEqual(true, raw_instruction.opcode.sign);
    try std.testing.expectEqual(true, raw_instruction.opcode.wide);
    try std.testing.expectEqual(0b11, raw_instruction.opcode.mod);
    try std.testing.expectEqual(0b110, raw_instruction.opcode.regOrMem);

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("si", result.args[0]);
    try std.testing.expectEqualStrings("2", result.args[1]);
}

test "decodeInstruction - JNZ" {
    const allocator = std.testing.allocator;
    const raw_instruction = try buildRawInstructionFromBytes(
        &[_]u8{ 0b1010_0011, 0b1000_0000, 0b0000_0001, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, raw_instruction);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("[384]", result.args[0]);
    try std.testing.expectEqualStrings("ax", result.args[1]);
}
