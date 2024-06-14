const std = @import("std");

// TODO duplication
fn concat_u8_to_u16(array: [2]u8) u16 {
    var result: u16 = array[0];
    result = result << 8;
    return result | array[1];
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

pub fn registerName(reg: u8, wide: bool) []const u8 {
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
pub fn effectiveAddressRegisters(regOrMem: u3, mod: u2, displacement: [2]u8) EffectiveAddress {
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

pub fn renderEffectiveAddress(effectiveAddress: EffectiveAddress, allocator: std.mem.Allocator) ![]const u8 {
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