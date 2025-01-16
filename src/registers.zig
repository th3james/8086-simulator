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
};

pub const Flags = struct {
    S: bool = false,
    Z: bool = false,

    pub fn print(self: Flags, writer: anytype) !void {
        const flag_info = @typeInfo(Flags);
        switch (flag_info) {
            .Struct => |struct_info| {
                inline for (struct_info.fields) |field_info| {
                    const flag_name = field_info.name;
                    const flag_value = @field(self, flag_name);

                    switch (@typeInfo(field_info.type)) {
                        .Bool => {
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
