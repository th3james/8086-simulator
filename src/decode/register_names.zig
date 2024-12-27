const std = @import("std");
const assert = std.debug.assert;

pub const Register = enum { al, cl, dl, bl, ah, ch, dh, bh, ax, cx, dx, bx, sp, bp, si, di, none };

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

pub fn getRegister(reg: u3, wide: bool) Register {
    assert(reg < registerMap.len);
    const registers = registerMap[reg];
    return if (wide) registers.wide else registers.narrow;
}

test "getRegister gets register" {
    try std.testing.expectEqual(Register.al, getRegister(0b000, false));
    try std.testing.expectEqual(Register.cx, getRegister(0b001, true));
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

pub const EffectiveAddress = struct { r1: Register, r2: Register, displacement: i16 };
// Table 4-10. R/M (Register/Memory) Field Encoding
pub fn effectiveAddressRegisters(regOrMem: u3, displacement: i16) EffectiveAddress {
    const names = effectiveAddressRegisterMap[regOrMem];

    return EffectiveAddress{ .r1 = names[0], .r2 = names[1], .displacement = displacement };
}

test "effective address options no displacement" {
    const result = effectiveAddressRegisters(0b000, 0b00);
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(0, result.displacement);
}

test "effective address options discarded displacement" {
    const result = effectiveAddressRegisters(0b000, 0b00);
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(0, result.displacement);
}

test "effective address options 8-bit displacement" {
    const result = effectiveAddressRegisters(0b000, 0b01);
    try std.testing.expectEqual(Register.bx, result.r1);
    try std.testing.expectEqual(Register.si, result.r2);
    try std.testing.expectEqual(1, result.displacement);
}

// TODO delete from here to end of file
fn writeEffectiveAddress(
    writer: anytype,
    effectiveAddress: EffectiveAddress,
) !void {
    try writer.writeAll("[");
    try writer.writeAll(@tagName(effectiveAddress.r1));

    if (effectiveAddress.r2 != Register.none) {
        try writer.writeAll(" + ");
        try writer.writeAll(@tagName(effectiveAddress.r2));
    }

    if (effectiveAddress.displacement != 0) {
        if (effectiveAddress.displacement > 0) {
            try writer.writeAll(" + ");
        } else {
            try writer.writeAll(" - ");
        }
        try std.fmt.formatInt(
            @abs(effectiveAddress.displacement),
            10,
            .lower,
            .{},
            writer,
        );
    }
    try writer.writeAll("]");
}

const MIN_EFFECTIVE_ADDR_LEN = 4; // [ax] is smallest possible string
pub fn renderEffectiveAddress(
    allocator: std.mem.Allocator,
    effectiveAddress: EffectiveAddress,
) ![]const u8 {
    var result_buffer = try std.ArrayList(u8).initCapacity(allocator, MIN_EFFECTIVE_ADDR_LEN);
    errdefer result_buffer.deinit();

    try writeEffectiveAddress(result_buffer.writer(), effectiveAddress);

    return result_buffer.toOwnedSlice();
}

test "render effective address no displacement" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = 0 };
    const result = try renderEffectiveAddress(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si]", result);
}

test "render effective address ignore zero register" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.si, .r2 = Register.none, .displacement = 0 };
    const result = try renderEffectiveAddress(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[si]", result);
}

test "render effective address with displacement" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = 250 };
    const result = try renderEffectiveAddress(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si + 250]", result);
}

test "render effective address with negative displacement" {
    var allocator = std.testing.allocator;
    const input = EffectiveAddress{ .r1 = Register.bx, .r2 = Register.si, .displacement = -37 };
    const result = try renderEffectiveAddress(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("[bx + si - 37]", result);
}
