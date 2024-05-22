const std = @import("std");

pub const DisplacementSize = enum {
    wide,
    narrow,
    none,
};

const OpcodeId = enum {
    mov,
    unknown,
};

const Opcode = struct {
    base: [2]u8,
    id: OpcodeId,
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
    const OPCODE_MASK: u8 = 0b11111100;
    // TODO convert bit masks to defines
    const opcode = inst[0] & OPCODE_MASK;
    switch (opcode) {
        0b10001000 => {
            return Opcode{ .base = inst, .id = OpcodeId.mov, .name = "mov", .displacement_size = DisplacementSize.none };
        },
        else => {
            return Opcode{ .base = inst, .id = OpcodeId.unknown, .name = "unknown", .displacement_size = DisplacementSize.none };
        },
    }
}

test "decodeOpcode - Unknown opcode decodes as unknown" {
    const result = decodeOpcode([_]u8{ 0b00000000, 0b00000000 });
    try std.testing.expectEqual(OpcodeId.unknown, result.id);
    try std.testing.expectEqualStrings("unknown", result.name);
}

test "decodeOpcode - Reg-to-reg MOV Decode" {
    const result = decodeOpcode([_]u8{ 0b10001000, 0b00000000 });
    try std.testing.expectEqual(OpcodeId.mov, result.id);
    try std.testing.expectEqualStrings("mov", result.name);
    try std.testing.expectEqual(DisplacementSize.none, result.displacement_size);
}

pub fn decodeInstruction(the_opcode: Opcode) !Instruction {
    var args = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer args.deinit();

    switch (the_opcode.id) {
        OpcodeId.mov => {
            const REG_DESTINATION_MASK: u8 = 0b00000010;
            const REG_OR_MEM_MASK: u8 = 0b00000111;
            const WIDE_MASK: u8 = 0b00000001;
            const MOD_MASK: u8 = 0b11000000;
            const REG_TO_REG_MASK: u8 = 0b11000000;
            const REG_MASK: u8 = 0b00111000;

            //std.debug.print("\n# Decoding Mov {b}, {b}\n", .{ inst[0], inst[1] });
            const regIsDestination = (the_opcode.base[0] & REG_DESTINATION_MASK) != 0;

            const wide = (the_opcode.base[0] & WIDE_MASK) != 0;
            //std.debug.print("\twide: {}, ", .{wide});
            const mod = the_opcode.base[1] & MOD_MASK;
            _ = mod;
            const regToReg = (the_opcode.base[1] & REG_TO_REG_MASK) == 192;

            const reg = (the_opcode.base[1] & REG_MASK) >> 3;
            //std.debug.print("\treg: {b}\n", .{reg});
            const regOrMem = the_opcode.base[1] & REG_OR_MEM_MASK;

            if (regToReg) {
                if (regIsDestination) {
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(reg, wide)));
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(regOrMem, wide)));
                } else {
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(regOrMem, wide)));
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(reg, wide)));
                }
            } else {
                try args.append(try std.heap.page_allocator.dupe(u8, "unsupported"));
            }
            return Instruction{ .args = try args.toOwnedSlice() };
        },
        OpcodeId.unknown => {
            return Instruction{ .args = try args.toOwnedSlice() };
        },
    }
}

test "decodeInstruction - MOV Decode - Reg to Reg only" {
    const opcode = decodeOpcode([_]u8{ 0b10001000, 0b00000000 });
    const unsupported = try decodeInstruction(opcode);
    defer unsupported.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 1), unsupported.args.len);
    try std.testing.expectEqualStrings("unsupported", unsupported.args[0]);
}

test "decodeInstruction - MOV Decode - Reg to Reg permutations" {
    const opcode = decodeOpcode([_]u8{ 0b10001000, 0b11000001 });
    const unsupported = try decodeInstruction(opcode);
    defer unsupported.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 2), unsupported.args.len);
    try std.testing.expectEqualStrings(registerName(0b1, false), unsupported.args[0]);
    try std.testing.expectEqualStrings(registerName(0b0, false), unsupported.args[1]);
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
