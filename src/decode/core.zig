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
                    try args.append(try std.heap.page_allocator.dupe(u8, "unsupported"));
                },
            }
            return Instruction{ .args = try args.toOwnedSlice() };
        },
        opcode_masks.OpcodeId.movImmediateToReg => {
            // TODO
            try args.append(try std.heap.page_allocator.dupe(u8, "unsupported mov immediate"));
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
