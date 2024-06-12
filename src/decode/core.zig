const std = @import("std");
const mov = @import("mov.zig");
const opcode_masks = @import("opcode_masks.zig");

pub const DisplacementSize = enum {
    wide,
    narrow,
    none,
};

const Opcode = struct {
    base: [2]u8,
    id: opcode_masks.OpcodeId,
    options: opcode_masks.OpcodeOptions,
    name: []const u8,
    displacement_size: DisplacementSize,
};

const Instruction = struct {
    args: []const []const u8,

    pub fn deinit(self: *const Instruction, allocator: *const std.mem.Allocator) void {
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
    }
};

pub fn decodeOpcode(inst: [2]u8) Opcode {
    var opcode_id = opcode_masks.OpcodeId.unknown;

    for (opcode_masks.OpcodeTable) |mask| {
        if ((inst[0] & mask.identifier_mask) == mask.identifier) {
            opcode_id = mask.id;
            break;
        }
    }
    const options = opcode_masks.parseOptions(opcode_id, inst);

    switch (opcode_id) {
        opcode_masks.OpcodeId.movRegOrMemToFromReg => {
            var displacement_size: DisplacementSize = DisplacementSize.none;
            switch (options.mod) {
                0b00 => {
                    if (options.regOrMem == 0b110) {
                        displacement_size = DisplacementSize.wide;
                    }
                },
                0b01 => {
                    displacement_size = DisplacementSize.narrow;
                },
                0b10 => {
                    displacement_size = DisplacementSize.wide;
                },
                else => {},
            }
            return Opcode{ .base = inst, .id = opcode_id, .options = options, .name = "mov", .displacement_size = displacement_size };
        },
        opcode_masks.OpcodeId.movImmediateToReg => {
            var displacement_size: DisplacementSize = DisplacementSize.none;

            if (options.wide) {
                displacement_size = DisplacementSize.narrow;
            }

            return Opcode{ .base = inst, .id = opcode_id, .options = options, .name = "mov", .displacement_size = displacement_size };
        },
        opcode_masks.OpcodeId.unknown => {
            std.debug.print("unknown opcode: {b} {b}\n", .{ inst[0], inst[1] });
            return Opcode{ .base = inst, .id = opcode_id, .options = options, .name = "unknown", .displacement_size = DisplacementSize.none };
        },
    }
}

test "decodeOpcode - Unknown opcode decodes as unknown" {
    const result = decodeOpcode([_]u8{ 0b00000000, 0b00000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.unknown, result.id);
    try std.testing.expectEqualStrings("unknown", result.name);
}

test "decodeOpcode - MOV Memory mode, no displacement" {
    const result = decodeOpcode([_]u8{ 0b10001000, 0b00000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.none, result.displacement_size);
}

test "decodeOpcode - MOV Memory mode, direct address" {
    const result = decodeOpcode([_]u8{ 0b10001000, 0b00000110 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.wide, result.displacement_size);
}

test "decodeOpcode - Reg-to-reg MOV Decode" {
    const result = decodeOpcode([_]u8{ 0b10001000, 0b11000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.none, result.displacement_size);
}

test "decodeOpcode - MOV Decode Memory mode 8-bit" {
    const result = decodeOpcode([_]u8{ 0b10001000, 0b01000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.narrow, result.displacement_size);
}

test "decodeOpcode - MOV Decode Memory mode 16-bit" {
    const result = decodeOpcode([_]u8{ 0b10001000, 0b10000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movRegOrMemToFromReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.wide, result.displacement_size);
}

test "decodeOpcode - MOV Immediate to register narrow" {
    const result = decodeOpcode([_]u8{ 0b10110001, 0b00000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movImmediateToReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.none, result.displacement_size);
}

test "decodeOpcode - MOV Immediate to register wide" {
    const result = decodeOpcode([_]u8{ 0b10111000, 0b00000000 });
    try std.testing.expectEqual(opcode_masks.OpcodeId.movImmediateToReg, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.narrow, result.displacement_size);
}

fn concat_u8_to_u16(array: [2]u8) u16 {
    var result: u16 = array[0];
    result = result << 8;
    return result | array[1];
}

pub fn decodeInstruction(opcode: Opcode, displacement: [2]u8) !Instruction {
    var args = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer args.deinit();

    switch (opcode.id) {
        opcode_masks.OpcodeId.movRegOrMemToFromReg => {
            switch (opcode.options.mod) {
                0b00 => { // Memory mode, no displacement
                    if (opcode.options.regOrMem == 0b110) { // Direct address
                        try args.append(try std.heap.page_allocator.dupe(u8, registerName(opcode.options.reg, opcode.options.wide)));
                        const memory_address = concat_u8_to_u16(displacement);
                        const memory_address_str = try std.fmt.allocPrint(std.heap.page_allocator, "{}", .{memory_address});
                        try args.append(memory_address_str);
                    } else {
                        // TODO this is duplicated
                        const effectiveAddress = effectiveAddressRegisters(opcode.options.regOrMem, opcode.options.mod, displacement);
                        if (mov.regIsDestination(opcode.base)) {
                            try args.append(try std.heap.page_allocator.dupe(
                                u8,
                                registerName(opcode.options.reg, opcode.options.wide),
                            ));
                            try args.append(try renderEffectiveAddress(effectiveAddress, std.heap.page_allocator));
                        } else {
                            try args.append(try renderEffectiveAddress(effectiveAddress, std.heap.page_allocator));
                            try args.append(try std.heap.page_allocator.dupe(
                                u8,
                                registerName(opcode.options.reg, opcode.options.wide),
                            ));
                        }
                    }
                },
                0b11 => { // Register to Register
                    if (mov.regIsDestination(opcode.base)) {
                        try args.append(try std.heap.page_allocator.dupe(u8, registerName(opcode.options.reg, opcode.options.wide)));
                        try args.append(try std.heap.page_allocator.dupe(u8, registerName(opcode.options.regOrMem, opcode.options.wide)));
                    } else {
                        try args.append(try std.heap.page_allocator.dupe(u8, registerName(opcode.options.regOrMem, opcode.options.wide)));
                        try args.append(try std.heap.page_allocator.dupe(u8, registerName(opcode.options.reg, opcode.options.wide)));
                    }
                },
                else => {
                    // TODO this is duplicated
                    const effectiveAddress = effectiveAddressRegisters(opcode.options.regOrMem, opcode.options.mod, displacement);
                    if (mov.regIsDestination(opcode.base)) {
                        try args.append(try std.heap.page_allocator.dupe(
                            u8,
                            registerName(opcode.options.reg, opcode.options.wide),
                        ));
                        try args.append(try renderEffectiveAddress(effectiveAddress, std.heap.page_allocator));
                    } else {
                        try args.append(try renderEffectiveAddress(effectiveAddress, std.heap.page_allocator));
                        try args.append(try std.heap.page_allocator.dupe(
                            u8,
                            registerName(opcode.options.reg, opcode.options.wide),
                        ));
                    }
                },
            }
            return Instruction{ .args = try args.toOwnedSlice() };
        },
        opcode_masks.OpcodeId.movImmediateToReg => {
            try args.append(try std.heap.page_allocator.dupe(u8, registerName(opcode.options.reg, opcode.options.wide)));

            if (opcode.options.wide) {
                const data_signed = concat_u8_to_u16([2]u8{
                    displacement[0],
                    opcode.base[1],
                });
                const data: i16 = @bitCast(data_signed);
                const data_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{data});
                try args.append(data_str);
            } else {
                const data: i8 = @bitCast(opcode.base[1]);
                const data_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{data});
                try args.append(data_str);
            }
            return Instruction{ .args = try args.toOwnedSlice() };
        },
        opcode_masks.OpcodeId.unknown => {
            return Instruction{ .args = try args.toOwnedSlice() };
        },
    }
}

test "decodeInstruction - MOV Decode - Reg to Reg permutations" {
    const opcode = decodeOpcode([_]u8{ 0b10001000, 0b11000001 });
    const result = try decodeInstruction(opcode, [_]u8{ 0, 0 });
    defer result.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings(registerName(0b0, false), result.args[1]);
}

test "decodeInstruction - MOV Decode - Direct address move" {
    const opcode = decodeOpcode([_]u8{ 0b10001000, 0b00000110 });
    const result = try decodeInstruction(opcode, [_]u8{ 0b1, 0b1 });
    defer result.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(registerName(0b0, false), result.args[0]);
    try std.testing.expectEqualStrings("257", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register narrow positive" {
    const opcode = decodeOpcode([_]u8{ 0b10110001, 0b00000110 });
    const result = try decodeInstruction(opcode, [_]u8{ 0b0, 0b0 });
    defer result.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register narrow negative" {
    const opcode = decodeOpcode([_]u8{ 0b10110001, 0b11111010 });
    const result = try decodeInstruction(opcode, [_]u8{ 0b0, 0b0 });
    defer result.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(registerName(0b1, false), result.args[0]);
    try std.testing.expectEqualStrings("-6", result.args[1]);
}

test "decodeInstruction - MOV Decode - Immediate to register wide" {
    const opcode = decodeOpcode([_]u8{ 0b10111001, 0b11111101 });
    const result = try decodeInstruction(opcode, [_]u8{ 0b11111111, 0b0 });
    defer result.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings(registerName(0b1, true), result.args[0]);
    try std.testing.expectEqualStrings("-3", result.args[1]);
}

const RegisterName = struct {
    narrow: []const u8,
    wide: []const u8,
};
const registerMap = [_]RegisterName{
    RegisterName{ .narrow = "al", .wide = "ax" },
    RegisterName{ .narrow = "cl", .wide = "cx" },
    RegisterName{ .narrow = "dl", .wide = "dx" },
    RegisterName{ .narrow = "bl", .wide = "bx" },
    RegisterName{ .narrow = "ah", .wide = "sp" },
    RegisterName{ .narrow = "ch", .wide = "bp" },
    RegisterName{ .narrow = "dh", .wide = "si" },
    RegisterName{ .narrow = "bh", .wide = "di" },
};

fn registerName(reg: u8, wide: bool) []const u8 {
    if (reg >= registerMap.len) {
        return "xx"; // Unknown or invalid register code
    }

    const names = registerMap[reg];
    return if (wide) names.wide else names.narrow;
}

test "registerName options" {
    try std.testing.expectEqualStrings("al", registerName(0b000, false));
    try std.testing.expectEqualStrings("cx", registerName(0b001, true));
}

const effectiveAddressRegisterMap = [_][2][2]u8{
    [2][2]u8{ [2]u8{ 'b', 'x' }, [2]u8{ 's', 'i' } },
    [2][2]u8{ [2]u8{ 'b', 'x' }, [2]u8{ 'd', 'i' } },
    [2][2]u8{ [2]u8{ 'b', 'p' }, [2]u8{ 's', 'i' } },
    [2][2]u8{ [2]u8{ 'b', 'p' }, [2]u8{ 'd', 'i' } },
    [2][2]u8{ [2]u8{ 's', 'i' }, [2]u8{ '0', '0' } },
    [2][2]u8{ [2]u8{ 'd', 'i' }, [2]u8{ '0', '0' } },
    [2][2]u8{ [2]u8{ 'b', 'p' }, [2]u8{ '0', '0' } },
    [2][2]u8{ [2]u8{ 'b', 'x' }, [2]u8{ '0', '0' } },
};

const EffectiveAddress = struct { r1: [2]u8, r2: [2]u8, displacement: u16 };
// Table 4-10. R/M (Register/Memory) Field Encoding
fn effectiveAddressRegisters(regOrMem: u3, mod: u2, displacement: [2]u8) EffectiveAddress {
    var offset: u16 = 0;
    const names = effectiveAddressRegisterMap[regOrMem];

    switch (mod) {
        0b01 => {
            offset = @intCast(displacement[0]);
        },
        0b10 => {
            offset = concat_u8_to_u16([2]u8{
                displacement[1],
                displacement[0],
            });
        },
        else => {},
    }
    return EffectiveAddress{ .r1 = names[0], .r2 = names[1], .displacement = offset };
}

test "effective address options no displacement" {
    const result = effectiveAddressRegisters(0b000, 0b00, [_]u8{ 0b0, 0b0 });
    try std.testing.expectEqualStrings("bx", &result.r1);
    try std.testing.expectEqualStrings("si", &result.r2);
    try std.testing.expectEqual(0, result.displacement);
}

test "effective address options 8-bit displacement" {
    const result = effectiveAddressRegisters(0b000, 0b01, [_]u8{ 0b1, 0b0 });
    try std.testing.expectEqualStrings("bx", &result.r1);
    try std.testing.expectEqualStrings("si", &result.r2);
    try std.testing.expectEqual(1, result.displacement);
}

test "effective address options 16-bit displacement" {
    const result = effectiveAddressRegisters(0b000, 0b10, [_]u8{ 0b10, 0b1 });
    try std.testing.expectEqualStrings("bx", &result.r1);
    try std.testing.expectEqualStrings("si", &result.r2);
    try std.testing.expectEqual(258, result.displacement);
}

fn renderEffectiveAddress(effectiveAddress: EffectiveAddress, allocator: std.mem.Allocator) ![]const u8 {
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    try args.append(try allocator.dupe(u8, &effectiveAddress.r1));
    if ((effectiveAddress.r2[0] != '0') and (effectiveAddress.r2[0] != '0')) {
        try args.append(try allocator.dupe(u8, &effectiveAddress.r2));
    }

    if (effectiveAddress.displacement != 0) {
        try args.append(
            try std.fmt.allocPrint(allocator, "{d}", .{effectiveAddress.displacement}),
        );
    }

    const args_str = try std.mem.join(allocator, " + ", try args.toOwnedSlice());
    defer allocator.free(args_str);
    return try std.fmt.allocPrint(allocator, "[{s}]", .{args_str});
}

test "render effective address no displacement" {
    const input = EffectiveAddress{ .r1 = [2]u8{ 'b', 'x' }, .r2 = [2]u8{ 's', 'i' }, .displacement = 0 };
    const result = try renderEffectiveAddress(input, std.heap.page_allocator);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si]", result);
}

test "render effective address ignore zero register" {
    const input = EffectiveAddress{ .r1 = [2]u8{ 's', 'i' }, .r2 = [2]u8{ '0', '0' }, .displacement = 0 };
    const result = try renderEffectiveAddress(input, std.heap.page_allocator);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("[si]", result);
}

test "render effective address with displacement" {
    const input = EffectiveAddress{ .r1 = [2]u8{ 'b', 'x' }, .r2 = [2]u8{ 's', 'i' }, .displacement = 250 };
    const result = try renderEffectiveAddress(input, std.heap.page_allocator);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si + 250]", result);
}
