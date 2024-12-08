const std = @import("std");
const assert = std.debug.assert;

const opcodes = @import("opcodes.zig");
const instruction_layout = @import("instruction_layout.zig");
const instruction = @import("instruction.zig");
const register_names = @import("register_names.zig");
const errors = @import("errors.zig");

const InstructionArgs = struct {
    args: []const []const u8,

    pub fn deinit(self: *const InstructionArgs, allocator: std.mem.Allocator) void {
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
    }
};

pub fn decodeArgs(allocator: std.mem.Allocator, inst: instruction.Instruction) !InstructionArgs {
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    switch (inst.opcode.id) {
        opcodes.OpcodeId.movRegOrMemToFromReg,
        opcodes.OpcodeId.addRegOrMemToEither,
        opcodes.OpcodeId.subRegOrMemToEither,
        opcodes.OpcodeId.cmpRegOrMemToReg,
        => {
            // TODO improve optional unwraps
            switch (inst.opcode.mod.?) {
                0b00 => { // Memory mode, no displacement
                    if (inst.opcode.regOrMem == 0b110) { // Direct address
                        try args.append(try allocator.dupe(u8, register_names.registerName(inst.opcode.reg.?, inst.opcode.wide.?)));
                        const memory_address = try inst.getDisplacement();
                        const memory_address_str = try std.fmt.allocPrint(allocator, "[{}]", .{memory_address});
                        try args.append(memory_address_str);
                    } else {
                        try appendEffectiveAddress(
                            allocator,
                            &args,
                            inst.opcode,
                            0,
                        );
                    }
                },
                0b11 => { // Register to Register
                    const regName = register_names.registerName(inst.opcode.reg.?, inst.opcode.wide.?);
                    const regOrMemName = register_names.registerName(inst.opcode.regOrMem.?, inst.opcode.wide.?);
                    if (inst.opcode.regIsDestination orelse false) {
                        try args.append(try allocator.dupe(u8, regName));
                        try args.append(try allocator.dupe(u8, regOrMemName));
                    } else {
                        try args.append(try allocator.dupe(u8, regOrMemName));
                        try args.append(try allocator.dupe(u8, regName));
                    }
                },
                else => {
                    try appendEffectiveAddress(
                        allocator,
                        &args,
                        inst.opcode,
                        try inst.getDisplacement(),
                    );
                },
            }
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.movImmediateToRegOrMem,
        opcodes.OpcodeId.addImmediateToRegOrMem,
        opcodes.OpcodeId.subImmediateToRegOrMem,
        opcodes.OpcodeId.cmpImmediateToRegOrMem,
        => {
            switch (inst.opcode.mod.?) {
                0b00 => { // Memory mode, no displacement
                    if (inst.opcode.regOrMem == 0b110) { // Direct address
                        const memory_address = try inst.getDisplacement();
                        const memory_address_str = try std.fmt.allocPrint(allocator, "[{}]", .{memory_address});
                        try args.append(memory_address_str);
                    } else {
                        const effectiveAddress = register_names.effectiveAddressRegisters(inst.opcode.regOrMem.?, // TODO can this unwrap be avoided?
                            inst.getDisplacement() catch |err| switch (err) {
                            errors.InstructionErrors.NoDisplacement => 0,
                            else => {
                                return err;
                            },
                        });
                        try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
                    }
                    const immediate = try inst.getImmediate();
                    const immediate_size = if (inst.opcode.wide.?)
                        "word"
                    else
                        "byte";
                    const immediate_str = try std.fmt.allocPrint(allocator, "{s} {}", .{
                        immediate_size,
                        immediate,
                    });
                    try args.append(immediate_str);
                },
                0b11 => { // Register to Register
                    const regOrMemName = register_names.registerName(inst.opcode.regOrMem.?, inst.opcode.wide.?);
                    try args.append(try allocator.dupe(u8, regOrMemName));
                    const immediate = try inst.getImmediate();
                    const immediate_str = try std.fmt.allocPrint(allocator, "{}", .{
                        immediate,
                    });
                    try args.append(immediate_str);
                },
                else => {
                    const effectiveAddress = register_names.effectiveAddressRegisters(inst.opcode.regOrMem.?, // TODO can this unwrap be avoided?
                        inst.getDisplacement() catch |err| switch (err) {
                        errors.InstructionErrors.NoDisplacement => 0,
                        else => {
                            return err;
                        },
                    });
                    try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
                    const immediate = try inst.getImmediate();
                    const immediate_size = if (inst.opcode.wide.?)
                        "word"
                    else
                        "byte";
                    const immediate_str = try std.fmt.allocPrint(allocator, "{s} {}", .{
                        immediate_size,
                        immediate,
                    });
                    try args.append(immediate_str);
                },
            }
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.movImmediateToReg => {
            try args.append(try allocator.dupe(u8, register_names.registerName(inst.opcode.reg.?, inst.opcode.wide.?)));

            if (inst.opcode.wide.?) {
                const data_signed = try inst.getImmediate();
                const data: i16 = @bitCast(data_signed);
                const data_str = try std.fmt.allocPrint(allocator, "{d}", .{data});
                try args.append(data_str);
            } else {
                const data: i8 = @bitCast(inst.bytes[1]);
                const data_str = try std.fmt.allocPrint(allocator, "{d}", .{data});
                try args.append(data_str);
            }
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.memoryToAccumulator => {
            // TODO handle wide
            try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            try args.append(try std.fmt.allocPrint(allocator, "[{d}]", .{
                try inst.getImmediate(),
            }));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.accumulatorToMemory => {
            try args.append(try std.fmt.allocPrint(allocator, "[{d}]", .{
                try inst.getImmediate(),
            }));
            // TODO handle wide
            try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        opcodes.OpcodeId.addImmediateToAccumulator,
        opcodes.OpcodeId.subImmediateToAccumulator,
        opcodes.OpcodeId.cmpImmediateWithAccumulator,
        => {
            if (inst.opcode.wide.?) {
                try args.append(try std.fmt.allocPrint(allocator, "ax", .{}));
            } else {
                try args.append(try std.fmt.allocPrint(allocator, "al", .{}));
            }
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{
                try inst.getImmediate(),
            }));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },

        .jmpIfZero,
        .jmpIfNotZero,
        .jmpIfLess,
        .jmpIfLessOrEq,
        .jmpIfBelow,
        .jmpIfBelowOrEq,
        .jmpIfParity,
        .jmpOnOverflow,
        .jmpOnSign,
        .jmpIfGreater,
        .jmpIfGreaterOrEq,
        .jmpIfAbove,
        .jmpIfAboveOrEq,
        .jmpIfParOdd,
        .jmpOnNotOverflow,
        .jmpOnNotSign,
        .loopCxTimes,
        .loopIfZero,
        .loopIfNotZero,
        .jmpIfCxZero,
        => {
            try args.append(try std.fmt.allocPrint(allocator, "{d}", .{
                try inst.getDisplacement(),
            }));
            return InstructionArgs{ .args = try args.toOwnedSlice() };
        },
    }
}

fn appendEffectiveAddress(
    allocator: std.mem.Allocator,
    args: *std.ArrayList([]const u8),
    opcode: opcodes.DecodedOpcode,
    displacement: i16,
) !void {
    const effectiveAddress = register_names.effectiveAddressRegisters(
        opcode.regOrMem.?, // TODO can this unwrap be avoided?
        displacement,
    );
    if (opcode.regIsDestination orelse false) {
        try args.append(try allocator.dupe(
            u8,
            register_names.registerName(opcode.reg.?, opcode.wide.?),
        ));
        try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
    } else {
        try args.append(try register_names.renderEffectiveAddress(allocator, effectiveAddress));
        try args.append(try allocator.dupe(
            u8,
            register_names.registerName(opcode.reg.?, opcode.wide.?),
        ));
    }
}

fn buildInstructionFromBytes(bytes: []const u8, length: u4) !instruction.Instruction {
    const result = try opcodes.decodeOpcode(bytes[0..length]);
    return instruction.Instruction{
        .bytes = bytes[0..],
        .opcode = result,
        .layout = instruction_layout.getInstructionLayout(result),
    };
}

test "decodeInstruction - JNZ" {
    const allocator = std.testing.allocator;
    const subject = try buildInstructionFromBytes(
        &[_]u8{ 0b1010_0011, 0b1000_0000, 0b0000_0001, 0, 0, 0 },
        2,
    );

    const result = try decodeArgs(allocator, subject);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.args.len);
    try std.testing.expectEqualStrings("[384]", result.args[0]);
    try std.testing.expectEqualStrings("ax", result.args[1]);
}
