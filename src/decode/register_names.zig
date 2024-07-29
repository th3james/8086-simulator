const std = @import("std");

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

pub fn registerName(reg: u3, wide: bool) []const u8 {
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

const EffectiveAddress = struct { r1: Register, r2: Register, displacement: i16 };
// Table 4-10. R/M (Register/Memory) Field Encoding
pub fn effectiveAddressRegisters(mod: u2, regOrMem: u3, displacement: i16) EffectiveAddress {
    // TODO is mod unnecessary
    const names = effectiveAddressRegisterMap[regOrMem];

    if (mod > 0) {
        return EffectiveAddress{ .r1 = names[0], .r2 = names[1], .displacement = displacement };
    } else {
        return EffectiveAddress{ .r1 = names[0], .r2 = names[1], .displacement = 0 };
    }
}

test "effective address options no displacement" {
    const result = effectiveAddressRegisters(0b00, 0b000, 0);
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(0, result.displacement);
}

test "effective address options discarded displacement" {
    const result = effectiveAddressRegisters(0b00, 0b000, 5);
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(0, result.displacement);
}

test "effective address options 8-bit displacement" {
    const result = effectiveAddressRegisters(0b01, 0b000, 1);
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(1, result.displacement);
}

test "effective address options 16-bit displacement" {
    const result = effectiveAddressRegisters(0b01, 0b000, 2303);
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(2303, result.displacement);
}

// TODO re-order arguments
pub fn renderEffectiveAddress(effectiveAddress: EffectiveAddress, allocator: std.mem.Allocator) ![]const u8 {
    // TODO this can be by optimised by reducing the number of allocations
    var args = std.ArrayList([]const u8).init(allocator);
    defer {
        for (args.items) |item| {
            allocator.free(item);
        }
        args.deinit();
    }

    try args.append(try allocator.dupe(u8, @tagName(effectiveAddress.r1)));
    if (effectiveAddress.r2 != Register.none) {
        try args.append(try allocator.dupe(u8, "+"));
        try args.append(try allocator.dupe(u8, @tagName(effectiveAddress.r2)));
    }

    if (effectiveAddress.displacement > 0) {
        try args.append(try allocator.dupe(u8, "+"));
        try args.append(
            try std.fmt.allocPrint(allocator, "{d}", .{effectiveAddress.displacement}),
        );
    } else if (effectiveAddress.displacement < 0) {
        try args.append(try allocator.dupe(u8, "-"));
        try args.append(
            try std.fmt.allocPrint(allocator, "{d}", .{@abs(effectiveAddress.displacement)}),
        );
    }

    const args_str = try std.mem.join(allocator, " ", args.items);
    defer allocator.free(args_str);
    return try std.fmt.allocPrint(allocator, "[{s}]", .{args_str});
}

test "render effective address no displacement" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = 0 };
    const result = try renderEffectiveAddress(input, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si]", result);
}

test "render effective address ignore zero register" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.si, .r2 = Register.none, .displacement = 0 };
    const result = try renderEffectiveAddress(input, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[si]", result);
}

test "render effective address with displacement" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = 250 };
    const result = try renderEffectiveAddress(input, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si + 250]", result);
}

test "render effective address with negative displacement" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = -37 };
    const result = try renderEffectiveAddress(input, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si - 37]", result);
}
