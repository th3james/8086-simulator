const std = @import("std");
const mov = @import("mov.zig");
const opcode_masks = @import("opcode_masks.zig");
const register_names = @import("register_names.zig");
const bit_utils = @import("bit_utils.zig");

pub const DisplacementSize = enum {
    wide,
    narrow,
    none,
};

const RawInstruction = struct {
    base: [6]u8,
    opcode: opcode_masks.DecodedOpcode,
    data_map: opcode_masks.InstructionDataMap,
};

const InstructionArgs = struct {
    args: []const []const u8,

    pub fn deinit(self: *const InstructionArgs, allocator: *const std.mem.Allocator) void {
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
    }
};

pub const Errors = error{InsufficientBytes};

// pub fn decodeOpcode(inst: []const u8) !Opcode {
//     var opcode_id = opcode_masks.OpcodeId.unknown;
//
//     for (opcode_masks.OpcodeTable) |mask| {
//         if ((inst[0] & mask.identifier_mask) == mask.identifier) {
//             opcode_id = mask.id;
//             break;
//         }
//     }
//
//     switch (opcode_id) {
//         opcode_masks.OpcodeId.movRegOrMemToFromReg => {
//             const displacement_size = switch (options.mod) {
//                 0b00 => if (options.regOrMem == 0b110)
//                     DisplacementSize.wide
//                 else
//                     DisplacementSize.none,
//                 0b01 => DisplacementSize.narrow,
//                 0b10 => DisplacementSize.wide,
//                 else => DisplacementSize.none,
//             };
//             return Opcode{ .base = inst, .id = opcode_id, .options = options, .name = "mov", .displacement_size = displacement_size };
//         },
//         opcode_masks.OpcodeId.movImmediateToRegOrMem => {
//             return Opcode{ .base = inst, .id = opcode_id, .optio{ns = options, .name = "mov", .displacement_size = DisplacementSize.none };
//         },
//         opcode_masks.OpcodeId.movImmediateToReg => {
//             var displacement_size: DisplacementSize = DisplacementSize.none;
//
//             if (options.wide) {
//                 displacement_size = DisplacementSize.narrow;
//             }
//
//             return Opcode{ .base = inst, .id = opcode_id, .options = options, .name = "mov", .displacement_size = displacement_size };
//         },
//         opcode_masks.OpcodeId.unknown => {
//             std.debug.print("unknown opcode: {b} {b}\n", .{ inst[0], inst[1] });
//             return Opcode{ .base = inst, .id = opcode_id, .options = options, .name = "unknown", .displacement_size = DisplacementSize.none };
//         },
//     }
// }

pub fn decodeOpcode(bytes: []const u8) !opcode_masks.DecodedOpcode {
    var decoded_opcode = opcode_masks.UnknownOpcode;

    const identifier: u16 = switch (bytes.len) {
        1 => {
            return Errors.InsufficientBytes;
        },
        else => @as(u16, bytes[0]) << 8 | bytes[1], // TODO this
    };

    for (opcode_masks.OpcodeTable) |mask| {
        if (mask.bytes_required <= bytes.len) {
            if ((identifier & mask.identifier_mask) == mask.identifier) {
                decoded_opcode = opcode_masks.DecodedOpcode{
                    .id = mask.id,
                    .name = mask.name,
                };

                break;
            }
        }
    }
    return decoded_opcode;
}

test "decodeOpcode - Unknown opcode with one byte returns InsufficientBytes error" {
    const result = decodeOpcode(&[_]u8{0b00000000});
    try std.testing.expectError(Errors.InsufficientBytes, result);
}

test "decodeOpcode - Unknown opcode with max bytes returns Unknown" {
    const result = try decodeOpcode(&[_]u8{ 0b00000000, 0b0 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.unknown, result.id);
    try std.testing.expectEqualStrings("???", result.name);
}

test "decodeOpcode - MOV Memory mode, no displacement" {
    const result = try decodeOpcode(&[_]u8{ 0b1000_1000, 0b0000_0000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}

test "decodeOpcode - MOV Memory mode, direct address" {
    const result = try decodeOpcode(&[_]u8{ 0b10001000, 0b00000110 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
}
//
// test "decodeOpcode - Reg-to-reg MOV Decode" {
//     const result = decodeOpcode([_]u8{ 0b10001000, 0b11000000 });
//     try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
//     try std.testing.expectEqualStrings("mov", result.name);
//     try std.testing.expectEqual(DisplacementSize.none, result.displacement_size);
// }
//
// test "decodeOpcode - MOV Decode Memory mode 8-bit" {
//     const result = decodeOpcode([_]u8{ 0b10001000, 0b01000000 });
//     try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
//     try std.testing.expectEqualStrings("mov", result.name);
//     try std.testing.expectEqual(DisplacementSize.narrow, result.displacement_size);
// }
//
// test "decodeOpcode - MOV Decode Memory mode 16-bit" {
//     const result = decodeOpcode([_]u8{ 0b10001000, 0b10000000 });
//     try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
//     try std.testing.expectEqualStrings("mov", result.name);
//     try std.testing.expectEqual(DisplacementSize.wide, result.displacement_size);
// }
//
// test "decodeOpcode - MOV Immediate to register narrow" {
//     const result = decodeOpcode([_]u8{ 0b10110001, 0b00000000 });
//     try std.testing.expectEqual(opcode_masks.OpcodeId.movImmediateToReg, result.id);
//     try std.testing.expectEqualStrings("mov", result.name);
//     try std.testing.expectEqual(DisplacementSize.none, result.displacement_size);
// }
//
// test "decodeOpcode - MOV Immediate to register wide" {
//     const result = decodeOpcode([_]u8{ 0b10111000, 0b00000000 });
//     try std.testing.expectEqual(opcode_masks.OpcodeId.movImmediateToReg, result.id);
//     try std.testing.expectEqualStrings("mov", result.name);
//     try std.testing.expectEqual(DisplacementSize.narrow, result.displacement_size);
// }

pub fn getInstructionDataMap(decoded_opcode: opcode_masks.DecodedOpcode) opcode_masks.InstructionDataMap {
    var result = opcode_masks.InstructionDataMap{};
    switch (decoded_opcode.id) {
        opcode_masks.OpcodeId.movRegOrMemToFromReg => {
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
        else => {},
    }
    return result;
}

test "getInstructionDataMap - MOV Memory mode, no displacement" {
    const decoded_opcode = opcode_masks.DecodedOpcode{
        .id = opcode_masks.OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .regOrMem = 0b000,
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
    };
    const result = getInstructionDataMap(decoded_opcode);
    try std.testing.expectEqual(2, result.displacement.?.start);
    try std.testing.expectEqual(4, result.displacement.?.end);
}

pub fn getInstructionLength(data_map: opcode_masks.InstructionDataMap) u4 {
    _ = data_map;
    return 0;
}

test "getInstructionLength - returns 0 when there is no additional data" {
    const in = opcode_masks.InstructionDataMap{};
    try std.testing.expectEqual(0, getInstructionLength(in));
}

pub fn decodeArgs(allocator: *std.mem.Allocator, raw: RawInstruction) !InstructionArgs {
    var args = std.ArrayList([]const u8).init(allocator.*);
    defer args.deinit();

    switch (raw.opcode.id) {
        opcode_masks.OpcodeId.movRegOrMemToFromReg => {
            switch (raw.opcode.mod) {
                0b00 => { // Memory mode, no displacement
                    if (raw.opcode.regOrMem == 0b110) { // Direct address
                        try args.append(try allocator.dupe(u8, register_names.registerName(raw.opcode.reg, raw.opcode.wide)));
                        const memory_address = bit_utils.concat_u8_to_u16(try raw.getDisplacement());
                        const memory_address_str = try std.fmt.allocPrint(allocator.*, "{}", .{memory_address});
                        try args.append(memory_address_str);
                    } else {
                        try appendEffectiveAddress(
                            allocator,
                            &args,
                            raw.opcode,
                            try raw.getDisplacement(),
                        );
                    }
                },
                0b11 => { // Register to Register
                    const regName = register_names.registerName(raw.opcode.reg, raw.opcode.wide);
                    const regOrMemName = register_names.registerName(raw.opcode.regOrMem, raw.opcode.wide);
                    if (mov.regIsDestination(raw.base[0..2])) {
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
        opcode_masks.OpcodeId.movImmediateToRegOrMem => {
            try args.append(try allocator.dupe(u8, "TODO Move Immediate To Register or Memory"));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },
        opcode_masks.OpcodeId.movImmediateToReg => {
            try args.append(try allocator.dupe(u8, register_names.registerName(raw.opcode.reg, raw.opcode.wide)));

            if (raw.opcode.wide) {
                const data_signed = bit_utils.concat_u8_to_u16(
                    try raw.getDisplacement(),
                );
                const data: i16 = @bitCast(data_signed);
                const data_str = try std.fmt.allocPrint(allocator.*, "{d}", .{data});
                try args.append(data_str);
            } else {
                const data: i8 = @bitCast(raw.base[1]);
                const data_str = try std.fmt.allocPrint(allocator.*, "{d}", .{data});
                try args.append(data_str);
            }
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },
        opcode_masks.OpcodeId.unknown => {
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },
    }
}

fn appendEffectiveAddress(
    allocator: *std.mem.Allocator,
    args: *std.ArrayList([]const u8),
    opcode: opcode_masks.DecodedOpcode,
    displacement: [2]u8,
) !void {
    const effectiveAddress = register_names.effectiveAddressRegisters(
        opcode.regOrMem,
        opcode.options.mod,
        displacement,
    );
    if (mov.regIsDestination(opcode.base)) {
        try args.append(try allocator.dupe(
            u8,
            register_names.registerName(opcode.reg, opcode.wide),
        ));
        try args.append(try register_names.renderEffectiveAddress(effectiveAddress, allocator.*));
    } else {
        try args.append(try register_names.renderEffectiveAddress(effectiveAddress, allocator.*));
        try args.append(try allocator.dupe(
            u8,
            register_names.registerName(opcode.options.reg, opcode.options.wide),
        ));
    }
}

// test "decodeInstruction - MOV Decode - Reg to Reg permutations" {
//     var allocator = std.testing.allocator;
//     const opcode = decodeOpcode([_]u8{ 0b10001000, 0b11000001 });
//     const result = try decodeInstruction(&allocator, opcode, [_]u8{ 0, 0 });
//     defer result.deinit(&allocator);
//     try std.testing.expectEqual(@as(usize, 2), result.args.len);
//     try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
//     try std.testing.expectEqualStrings(register_names.registerName(0b0, false), result.args[1]);
// }
//
// test "decodeInstruction - MOV Decode - Direct address move" {
//     var allocator = std.testing.allocator;
//     const opcode = decodeOpcode([_]u8{ 0b10001000, 0b00000110 });
//     const result = try decodeInstruction(&allocator, opcode, [_]u8{ 0b1, 0b1 });
//     defer result.deinit(&allocator);
//     try std.testing.expectEqual(@as(usize, 2), result.args.len);
//     try std.testing.expectEqualStrings(register_names.registerName(0b0, false), result.args[0]);
//     try std.testing.expectEqualStrings("257", result.args[1]);
// }
//
// test "decodeInstruction - MOV reg or memory" {
//     var allocator = std.testing.allocator;
//     const opcode = decodeOpcode([_]u8{ 0b1000_1011, 0b0100_0001 });
//     const result = try decodeInstruction(&allocator, opcode, [_]u8{ 0b1101_1011, 0b0 });
//     defer result.deinit(&allocator);
//     try std.testing.expectEqual(@as(usize, 2), result.args.len);
//     try std.testing.expectEqualStrings("ax", result.args[0]);
//     try std.testing.expectEqualStrings("[bx + di - 37]", result.args[1]);
// }
//
// test "decodeInstruction - MOV Decode - Immediate to register narrow positive" {
//     var allocator = std.testing.allocator;
//     const opcode = decodeOpcode([_]u8{ 0b10110001, 0b00000110 });
//     const result = try decodeInstruction(&allocator, opcode, [_]u8{ 0b0, 0b0 });
//     defer result.deinit(&allocator);
//     try std.testing.expectEqual(@as(usize, 2), result.args.len);
//     try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
//     try std.testing.expectEqualStrings("6", result.args[1]);
// }
//
// test "decodeInstruction - MOV Decode - Immediate to register narrow negative" {
//     var allocator = std.testing.allocator;
//     const opcode = decodeOpcode([_]u8{ 0b10110001, 0b11111010 });
//     const result = try decodeInstruction(&allocator, opcode, [_]u8{ 0b0, 0b0 });
//     defer result.deinit(&allocator);
//     try std.testing.expectEqual(@as(usize, 2), result.args.len);
//     try std.testing.expectEqualStrings(register_names.registerName(0b1, false), result.args[0]);
//     try std.testing.expectEqualStrings("-6", result.args[1]);
// }
//
// test "decodeInstruction - MOV Decode - Immediate to register wide" {
//     var allocator = std.testing.allocator;
//     const opcode = decodeOpcode([_]u8{ 0b10111001, 0b11111101 });
//     const result = try decodeInstruction(&allocator, opcode, [_]u8{ 0b11111111, 0b0 });
//     defer result.deinit(&allocator);
//     try std.testing.expectEqual(@as(usize, 2), result.args.len);
//     try std.testing.expectEqualStrings(register_names.registerName(0b1, true), result.args[0]);
//     try std.testing.expectEqualStrings("-3", result.args[1]);
// }
