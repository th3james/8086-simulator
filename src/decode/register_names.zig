const std = @import("std");
const bit_utils = @import("bit_utils.zig");

const Register = enum { al, cl, dl, bl, ah, ch, dh, bh, ax, cx, dx, bx, sp, bp, si, di, none };

const RegisterInfo = struct {
    narrow: Register,
    wide: Register,
};
const registerMap = [_]RegisterInfo{
    RegisterInfo{ .narrow = Register.al, .wide = Register.ax },
    RegisterInfo{ .narrow = Register.cl, .wide = Register.cx },
    RegisterInfo{ .narrow = Register.dl, .wide = Register.dx },
    RegisterInfo{ .narrow = Register.bl, .wide = Register.bx },
    RegisterInfo{ .narrow = Register.ah, .wide = Register.sp },
    RegisterInfo{ .narrow = Register.ch, .wide = Register.bp },
    RegisterInfo{ .narrow = Register.dh, .wide = Register.si },
    RegisterInfo{ .narrow = Register.bh, .wide = Register.di },
};

pub fn registerName(reg: u8, wide: bool) []const u8 {
    if (reg >= registerMap.len) {
        return "xx"; // Unknown or invalid register code
    }

    const names = registerMap[reg];
    return @tagName(if (wide) names.wide else names.narrow);
}

test "registerName options" {
    try std.testing.expectEqualStrings("al", registerName(0b000, false));
    try std.testing.expectEqualStrings("cx", registerName(0b001, true));
}

const effectiveAddressRegisterMap = [_][2]Register{
    .{ Register.bx, Register.si },
    .{ Register.bx, Register.di },
    .{ Register.bp, Register.si },
    .{ Register.bp, Register.di },
    .{ Register.si, Register.none },
    .{ Register.di, Register.none },
    .{ Register.bp, Register.none },
    .{ Register.bx, Register.none },
};

const EffectiveAddress = struct { r1: Register, r2: Register, displacement: u16 };
// Table 4-10. R/M (Register/Memory) Field Encoding
pub fn effectiveAddressRegisters(regOrMem: u3, mod: u2, displacement: [2]u8) EffectiveAddress {
    var offset: u16 = 0;
    const names = effectiveAddressRegisterMap[regOrMem];

    switch (mod) {
        0b01 => {
            offset = @intCast(displacement[0]);
        },
        0b10 => {
            offset = bit_utils.concat_u8_to_u16([2]u8{
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
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(0, result.displacement);
}

test "effective address options 8-bit displacement" {
    const result = effectiveAddressRegisters(0b000, 0b01, [_]u8{ 0b1, 0b0 });
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(1, result.displacement);
}

test "effective address options 16-bit displacement" {
    const result = effectiveAddressRegisters(0b000, 0b10, [_]u8{ 0b10, 0b1 });
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(258, result.displacement);
}

pub fn renderEffectiveAddress(effectiveAddress: EffectiveAddress, allocator: std.mem.Allocator) ![]const u8 {
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    try args.append(@tagName(effectiveAddress.r1));
    if (effectiveAddress.r2 != Register.none) {
        try args.append(@tagName(effectiveAddress.r2));
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
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = 0 };
    const result = try renderEffectiveAddress(input, std.heap.page_allocator);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si]", result);
}

test "render effective address ignore zero register" {
    const input = EffectiveAddress{ .r1 = Register.si, .r2 = Register.none, .displacement = 0 };
    const result = try renderEffectiveAddress(input, std.heap.page_allocator);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("[si]", result);
}

test "render effective address with displacement" {
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = 250 };
    const result = try renderEffectiveAddress(input, std.heap.page_allocator);
    defer std.heap.page_allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si + 250]", result);
}
