const std = @import("std");
const decode = @import("decode/register_names.zig");

pub const Registers = struct {
    al: u8 = 0,
    ax: u16 = 0,
    bl: u8 = 0,
    bx: u16 = 0,
    cl: u8 = 0,
    cx: u16 = 0,
    dl: u8 = 0,
    dx: u16 = 0,
    ah: u8 = 0,
    sp: u16 = 0,
    ch: u8 = 0,
    bp: u16 = 0,
    dh: u8 = 0,
    si: u16 = 0,
    bh: u8 = 0,
    di: u16 = 0,

    pub fn print(self: Registers, writer: anytype) !void {
        const info = @typeInfo(Registers);

        switch (info) {
            .@"struct" => |struct_info| {
                inline for (struct_info.fields) |field_info| {
                    const reg_name = field_info.name;
                    const reg_value = @field(self, reg_name);

                    switch (@typeInfo(field_info.type)) {
                        .int => {
                            if (reg_value != 0) {
                                try writer.print("      {s}: 0x{x:0>4} ({d})\n", .{ reg_name, reg_value, reg_value });
                            }
                        },
                        else => unreachable,
                    }
                }
            },
            else => unreachable,
        }
    }

    // TODO wrong case for name - printChanges
    pub fn print_changes(self: Registers, previous: Registers, writer: anytype) !void {
        const info = @typeInfo(Registers);

        switch (info) {
            .@"struct" => |struct_info| {
                inline for (struct_info.fields) |field_info| {
                    const reg_name = field_info.name;
                    const old_value = @field(previous, reg_name);
                    const new_value = @field(self, reg_name);

                    switch (@typeInfo(field_info.type)) {
                        .int => {
                            if (old_value != new_value) {
                                try writer.print("{s}:0x{x}->0x{x} ", .{ reg_name, old_value, new_value });
                            }
                        },
                        else => unreachable,
                    }
                }
            },
            else => unreachable,
        }
    }

    pub fn calculateEffectiveAddress(self: *const Registers, effective_address: decode.EffectiveAddress) u16 {
        var result = getRegVal(self, effective_address.r1);
        if (effective_address.r1 != .none) {
            result += getRegVal(self, effective_address.r2);
        }
        return if (effective_address.displacement < 0) blk: {
            const abs_displacement = @abs(effective_address.displacement);
            std.debug.assert(abs_displacement < result);
            break :blk result - abs_displacement;
        } else blk: {
            break :blk std.math.add(
                u16,
                result,
                @intCast(effective_address.displacement),
            ) catch unreachable;
        };
    }
};

test "calculateEffectiveAddress with BX+SI and positive displacement" {
    const regs = Registers{
        .bx = 0x1000,
        .si = 0x0100,
    };

    const effective_address = decode.EffectiveAddress{
        .r1 = decode.Register.bx,
        .r2 = decode.Register.si,
        .displacement = 0x0010,
    };

    try std.testing.expectEqual(
        @as(u16, 0x1110),
        regs.calculateEffectiveAddress(effective_address),
    );
}

pub const Flags = struct {
    P: bool = false,
    S: bool = false,
    Z: bool = false,

    pub fn print(self: Flags, writer: anytype) !void {
        const flag_info = @typeInfo(Flags);
        switch (flag_info) {
            .@"struct" => |struct_info| {
                inline for (struct_info.fields) |field_info| {
                    const flag_name = field_info.name;
                    const flag_value = @field(self, flag_name);

                    switch (@typeInfo(field_info.type)) {
                        .bool => {
                            if (flag_value) {
                                try writer.writeAll(flag_name);
                            }
                        },
                        else => unreachable,
                    }
                }
            },
            else => unreachable,
        }
    }

    pub fn update(self: *Flags, result_value: u16) void {
        self.S = (result_value & 0b1000_0000_0000_0000) != 0;
        self.Z = result_value == 0;

        // Only the least signficant byte is checked for parity
        var ones: u4 = 0;
        var val: u8 = @truncate(result_value);
        while (val != 0) : (val &= val - 1) {
            ones += 1;
        }
        // Parity flag is set if number of 1s is even
        self.P = (ones & 1) == 0;
    }

    test "S flag is set when result is negative" {
        var flags = Flags{};

        // Test positive number (MSB = 0)
        flags.update(0x7FFF);
        try std.testing.expect(!flags.S);

        // Test negative number (MSB = 1)
        flags.update(0x8000);
        try std.testing.expect(flags.S);

        // Test another positive number
        flags.update(0x0001);
        try std.testing.expect(!flags.S);

        // Test another negative number
        flags.update(0xFFFF);
        try std.testing.expect(flags.S);
    }

    test "Z flag is set when result is zero" {
        var flags = Flags{};

        // Test positive number (MSB = 0)
        flags.update(0x000F);
        try std.testing.expect(!flags.Z);

        // Test negative number (MSB = 1)
        flags.update(0x8000);
        try std.testing.expect(flags.S);

        // Test another positive number
        flags.update(0x0001);
        try std.testing.expect(!flags.S);

        // Test another negative number
        flags.update(0xFFFF);
        try std.testing.expect(flags.S);
    }
};

pub fn getWideReg(regs: *Registers, reg: decode.Register) *u16 {
    return switch (reg) {
        .ax => &regs.ax,
        .cx => &regs.cx,
        .dx => &regs.dx,
        .bx => &regs.bx,
        .sp => &regs.sp,
        .bp => &regs.bp,
        .si => &regs.si,
        .di => &regs.di,
        else => unreachable,
    };
}

pub fn getRegVal(regs: *const Registers, reg: decode.Register) u16 {
    return switch (reg) {
        .ax => regs.ax,
        .cx => regs.cx,
        .dx => regs.dx,
        .bx => regs.bx,
        .sp => regs.sp,
        .bp => regs.bp,
        .si => regs.si,
        .di => regs.di,
        .al => regs.al,
        .cl => regs.cl,
        .dl => regs.dl,
        .bl => regs.bl,
        .ah => regs.ah,
        .ch => regs.ch,
        .dh => regs.dh,
        .bh => regs.bh,
        .none => 0,
    };
}
