const std = @import("std");

const decode_arguments = @import("arguments.zig");
const registers = @import("register_names.zig");

fn operandToString(writer: anytype, argument: decode_arguments.Operand) !void {
    switch (argument) {
        .register => |*r| {
            try writer.writeAll(@tagName(r.*));
        },
        .absolute_address => |*a| {
            try writer.writeAll("[");
            try std.fmt.formatInt(
                @abs(a.*),
                10,
                .lower,
                .{},
                writer,
            );
            try writer.writeAll("]");
        },
        .relative_address => |*a| {
            try writer.print("{d}", .{a.*});
        },
        .effective_address => |*addr| {
            try writer.writeAll("[");
            if (addr.r1 != registers.Register.none) {
                try writer.writeAll(@tagName(addr.r1));
            }

            if (addr.r2 != registers.Register.none) {
                try writer.writeAll(" + ");
                try writer.writeAll(@tagName(addr.r2));
            }

            if (addr.displacement != 0) {
                if (addr.r1 != registers.Register.none) {
                    if (addr.displacement > 0) {
                        try writer.writeAll(" + ");
                    } else {
                        try writer.writeAll(" - ");
                    }
                }

                try std.fmt.formatInt(
                    @abs(addr.displacement),
                    10,
                    .lower,
                    .{},
                    writer,
                );
            }
            try writer.writeAll("]");
        },
        .immediate => |imm| {
            try writer.print("{d}", .{imm.value});
        },
        else => {
            try writer.writeAll("welp");
        },
    }
}

test "operandToString - EffectiveAddress with one register" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();
    const address = registers.EffectiveAddress{
        .r1 = registers.Register.si,
        .r2 = registers.Register.none,
        .displacement = 0,
    };

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .effective_address = address },
    );

    try std.testing.expectEqualStrings("[si]", result_buffer.items);
}

test "operandToString - EffectiveAddress no displacements" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();
    const address = registers.EffectiveAddress{
        .r1 = registers.Register.bx,
        .r2 = registers.Register.si,
        .displacement = 0,
    };

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .effective_address = address },
    );

    try std.testing.expectEqualStrings("[bx + si]", result_buffer.items);
}

test "operandToString - EffectiveAddress with positive displacement" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();
    const address = registers.EffectiveAddress{
        .r1 = registers.Register.bx,
        .r2 = registers.Register.di,
        .displacement = 250,
    };

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .effective_address = address },
    );

    try std.testing.expectEqualStrings("[bx + di + 250]", result_buffer.items);
}

test "operandToString - EffectiveAddress with negative displacement" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();
    const address = registers.EffectiveAddress{
        .r1 = registers.Register.bx,
        .r2 = registers.Register.di,
        .displacement = -37,
    };

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .effective_address = address },
    );

    try std.testing.expectEqualStrings("[bx + di - 37]", result_buffer.items);
}

test "operandToString - EffectiveAddress effective address with none registers" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();
    const address = registers.EffectiveAddress{ .r1 = .none, .r2 = .none, .displacement = 42 };

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .effective_address = address },
    );

    try std.testing.expectEqualStrings("[42]", result_buffer.items);
}

test "operandToString - register defined immediate" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .immediate = .{ .value = 7, .size = .registerDefined } },
    );

    try std.testing.expectEqualStrings("7", result_buffer.items);
}

test "operandToString - byte immediate" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .immediate = .{ .value = 7, .size = .byte } },
    );

    try std.testing.expectEqualStrings("7", result_buffer.items);
}

test "operandToString - word immediate" {
    var result_buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 14);
    defer result_buffer.deinit();

    try operandToString(
        result_buffer.writer(),
        decode_arguments.Operand{ .immediate = .{ .value = 7, .size = .word } },
    );

    try std.testing.expectEqualStrings("7", result_buffer.items);
}

// cp ax, bx
const MIN_INSTRUCTION_STR_LEN = 9;
pub fn instructionToString(
    allocator: std.mem.Allocator,
    mnemonic: []const u8,
    args: [2]decode_arguments.Operand,
) ![]const u8 {
    var result_buffer = try std.ArrayList(u8).initCapacity(allocator, MIN_INSTRUCTION_STR_LEN);
    errdefer result_buffer.deinit();

    const writer = result_buffer.writer();

    try writer.writeAll(mnemonic);
    try writer.writeAll(" ");

    switch (args[0]) {
        .effective_address, .absolute_address => {
            switch (args[1]) {
                .immediate => {
                    try writer.print("{s} ", .{@tagName(args[1].immediate.size)});
                },
                else => {},
            }
        },
        else => {},
    }

    try operandToString(writer, args[0]);
    if (args[1] != .none) {
        try writer.writeAll(", ");
        switch (args[1]) {
            .absolute_address, .effective_address => {
                switch (args[0]) {
                    .immediate => {
                        try writer.print("{s} ", .{@tagName(args[1].immediate.size)});
                    },
                    else => {},
                }
            },
            else => {},
        }
        try operandToString(writer, args[1]);
    }

    return result_buffer.toOwnedSlice();
}

test "instructionToString - register arguments" {
    const allocator = std.testing.allocator;
    const args = [_]decode_arguments.Operand{
        .{ .register = registers.Register.cl },
        .{ .register = registers.Register.al },
    };
    const result = try instructionToString(
        std.testing.allocator,
        "mov",
        args,
    );
    defer allocator.free(result);

    try std.testing.expectEqualStrings("mov cl, al", result);
}

test "instructionToString - absolute address arguments" {
    const allocator = std.testing.allocator;
    const args = [_]decode_arguments.Operand{
        .{ .register = registers.Register.al },
        .{ .absolute_address = 257 },
    };
    const result = try instructionToString(
        std.testing.allocator,
        "mov",
        args,
    );
    defer allocator.free(result);

    try std.testing.expectEqualStrings("mov al, [257]", result);
}

test "instructionToString - immediate word to absolute address" {
    const allocator = std.testing.allocator;
    const args = [_]decode_arguments.Operand{
        .{ .absolute_address = 257 },
        .{ .immediate = .{ .value = 7, .size = .word } },
    };
    const result = try instructionToString(
        std.testing.allocator,
        "mov",
        args,
    );
    defer allocator.free(result);

    try std.testing.expectEqualStrings("mov word [257], 7", result);
}

test "instructionToString - absolute address to byte register" {
    const allocator = std.testing.allocator;
    const args = [_]decode_arguments.Operand{
        .{ .register = registers.Register.bl },
        .{ .absolute_address = 1337 },
    };
    const result = try instructionToString(
        std.testing.allocator,
        "mov",
        args,
    );
    defer allocator.free(result);

    try std.testing.expectEqualStrings("mov bl, [1337]", result);
}

test "instructionToString - jmp with negative relative address argument" {
    const allocator = std.testing.allocator;
    const args = [_]decode_arguments.Operand{
        .{ .relative_address = -257 },
        .none,
    };
    const result = try instructionToString(
        std.testing.allocator,
        "jmp",
        args,
    );
    defer allocator.free(result);

    try std.testing.expectEqualStrings("jmp -257", result);
}
