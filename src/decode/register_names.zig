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
