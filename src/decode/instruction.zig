const std = @import("std");
const opcodes = @import("opcodes.zig");
const instruction_layout = @import("instruction_layout.zig");
const errors = @import("errors.zig");

pub const Instruction = struct {
    bytes: []const u8,
    opcode: opcodes.DecodedOpcode,
    layout: instruction_layout.InstructionLayout,

    fn extractValue(self: *const Instruction, field: instruction_layout.InstructionField) errors.InstructionErrors!i16 {
        if (field.end - field.start == 1) {
            return @as(i16, @as(i8, @bitCast(self.bytes[field.start])));
        } else if (field.end - field.start == 2) {
            return @as(i16, @bitCast(@as(u16, self.bytes[field.end - 1]) << 8 | @as(u16, self.bytes[field.start])));
        } else {
            return errors.InstructionErrors.UnhandledRange;
        }
    }

    pub fn getDisplacement(self: *const Instruction) errors.InstructionErrors!i16 {
        const displacement_location = self.layout.displacement orelse return errors.InstructionErrors.NoDisplacement;
        return self.extractValue(displacement_location);
    }

    pub fn getImmediate(self: *const Instruction) errors.InstructionErrors!i16 {
        const immediate_location = self.layout.immediate orelse return errors.InstructionErrors.NoImmediate;
        return self.extractValue(immediate_location);
    }
};

test "Instruction.getDisplacement - errors when no data map" {
    var bytes = [_]u8{ 0b10111001, 0b10, 0b1, 0, 0, 0 };
    const in = Instruction{
        .bytes = &bytes,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 1 },
        .layout = .{},
    };
    try std.testing.expectError(errors.InstructionErrors.NoDisplacement, in.getDisplacement());
}

test "Instruction.getDisplacement - positive narrow" {
    var bytes = [_]u8{ 0b10111001, 1, 0, 0, 0, 0 };
    const in = Instruction{
        .bytes = &bytes,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 1 },
        .layout = .{
            .displacement = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(1, try in.getDisplacement());
}

test "Instruction.getDisplacement - negative narrow is sign-extended" {
    var bytes = [_]u8{ 0b10111001, 0b1101_1011, 0, 0, 0, 0 };
    const in = Instruction{
        .bytes = &bytes,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .layout = .{
            .displacement = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(-37, try in.getDisplacement());
}

test "Instruction.getDisplacement - wide" {
    var bytes = [_]u8{ 0b10111001, 0, 0b1, 0, 0, 0 };
    const in = Instruction{
        .bytes = &bytes,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .layout = .{
            .displacement = .{
                .start = 1,
                .end = 3,
            },
        },
    };
    try std.testing.expectEqual(256, try in.getDisplacement());
}

test "Instruction.getImmediate - errors when no data map" {
    var bytes = [_]u8{ 0b10111001, 0b10, 0b1, 0, 0, 0 };
    const in = Instruction{
        .bytes = &bytes,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .layout = .{},
    };
    try std.testing.expectError(errors.InstructionErrors.NoImmediate, in.getImmediate());
}

test "Instruction.getImmediate - narrow" {
    var bytes = [_]u8{ 0b10111001, 0b10, 0, 0, 0, 0 };
    const in = Instruction{
        .bytes = &bytes,
        .opcode = .{ .id = .movImmediateToReg, .name = "nvm", .length = 2 },
        .layout = .{
            .immediate = .{
                .start = 1,
                .end = 2,
            },
        },
    };
    try std.testing.expectEqual(2, try in.getImmediate());
}
