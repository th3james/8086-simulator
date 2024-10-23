const std = @import("std");
const opcode = @import("opcode.zig");
const instruction_data = @import("instruction_data.zig");
const errors = @import("errors.zig");

pub const RawInstruction = struct {
    base: []const u8,
    opcode: opcode.DecodedOpcode,
    data_map: instruction_data.InstructionDataMap,

    fn extractValue(self: *const RawInstruction, field: instruction_data.InstructionField) errors.InstructionErrors!i16 {
        if (field.end - field.start == 1) {
            return @as(i16, @as(i8, @bitCast(self.base[field.start])));
        } else if (field.end - field.start == 2) {
            return @as(i16, @bitCast(@as(u16, self.base[field.end - 1]) << 8 | @as(u16, self.base[field.start])));
        } else {
            return errors.InstructionErrors.UnhandledRange;
        }
    }

    pub fn getDisplacement(self: *const RawInstruction) errors.InstructionErrors!i16 {
        const displacement_map = self.data_map.displacement orelse return errors.InstructionErrors.NoDisplacement;
        return self.extractValue(displacement_map);
    }

    pub fn getData(self: *const RawInstruction) errors.InstructionErrors!i16 {
        const data_map = self.data_map.data orelse return errors.InstructionErrors.NoData;
        return self.extractValue(data_map);
    }
};

test "RawInstruction.getDisplacement - errors when no data map" {
    var base = [_]u8{ 0b10111001, 0b10, 0b1, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 1 },
        .data_map = .{},
    };
    try std.testing.expectError(errors.InstructionErrors.NoDisplacement, in.getDisplacement());
}

test "RawInstruction.getDisplacement - positive narrow" {
    var base = [_]u8{ 0b10111001, 1, 0, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 1 },
        .data_map = .{
            .displacement = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(1, try in.getDisplacement());
}

test "RawInstruction.getDisplacement - negative narrow is sign-extended" {
    var base = [_]u8{ 0b10111001, 0b1101_1011, 0, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{
            .displacement = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(-37, try in.getDisplacement());
}

test "RawInstruction.getDisplacement - wide" {
    var base = [_]u8{ 0b10111001, 0, 0b1, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{
            .displacement = .{
                .start = 1,
                .end = 3,
            },
        },
    };
    try std.testing.expectEqual(256, try in.getDisplacement());
}

test "RawInstruction.getData - errors when no data map" {
    var base = [_]u8{ 0b10111001, 0b10, 0b1, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{},
    };
    try std.testing.expectError(errors.InstructionErrors.NoData, in.getData());
}

test "RawInstruction.getData - narrow" {
    var base = [_]u8{ 0b10111001, 0b10, 0, 0, 0, 0 };
    const in = RawInstruction{
        .base = &base,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .data_map = .{
            .data = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(2, try in.getData());
}
