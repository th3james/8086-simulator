const std = @import("std");
const assert = std.debug.assert;

const memory = @import("memory.zig");
const reg = @import("registers.zig");
const opcodes = @import("decode/opcodes.zig");
const instruction_layout = @import("decode/instruction_layout.zig");
const decode_errors = @import("decode/errors.zig");
const instruction = @import("decode/instruction.zig");
const decode_arguments = @import("decode/arguments.zig");
const decode_print = @import("decode/print.zig");
const register_names = @import("decode/register_names.zig");

const InvalidBinaryErrors = error{ IncompleteInstruction, MissingDisplacementError };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parsed_args = parseArgs(args) catch {
        std.debug.print("Usage: {s} |--execute| <file_path>\n", .{args[0]});
        std.process.exit(1);
    };

    // Init system
    var registers = reg.Registers{};
    var flags = reg.Flags{};
    var instruction_pointer: u16 = 0;

    const emu_mem = try allocator.create(memory.Memory);
    defer _ = allocator.destroy(emu_mem);

    const program_len = try memory.loadFromFile(parsed_args.file_path, emu_mem);
    assert(program_len > 0);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    if (!parsed_args.execute) {
        try stdout.print("bits 16\n", .{});
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Main loop through memory
    while (instruction_pointer < program_len) {
        _ = arena.reset(.retain_capacity);
        const arena_allocator = arena.allocator();

        const initial_ip = instruction_pointer;

        // Decode
        const opcode = try decodeOpcodeAtAddress(emu_mem, instruction_pointer, program_len);

        const layout = instruction_layout.getInstructionLayout(opcode);

        const instruction_end = instruction_pointer + instruction_layout.getInstructionLength(opcode.length, layout);
        assert(instruction_end > instruction_pointer);
        assert((instruction_end - instruction_pointer) <= instruction_layout.MAX_INSTRUCTION_LENGTH);

        const instruction_bytes = if (instruction_end <= program_len)
            memory.sliceMemory(emu_mem, instruction_pointer, instruction_end)
        else
            return InvalidBinaryErrors.IncompleteInstruction;
        instruction_pointer = instruction_end;

        const current_instruction = instruction.Instruction{
            .bytes = instruction_bytes,
            .opcode = opcode,
            .layout = layout,
        };

        const instruction_args = try decode_arguments.decodeArguments(current_instruction);

        const instruction_str = try decode_print.instructionToString(
            arena_allocator,
            opcode.name,
            instruction_args,
        );
        try stdout.print("{s}", .{instruction_str});

        // Execute
        if (parsed_args.execute) {
            const initial_registers = registers;
            const initial_flags = flags;

            switch (instruction_args[0]) {
                .register => {
                    // TODO Only supporting wide addresses for now
                    assert(register_names.isWide(instruction_args[0].register));

                    const target_reg = reg.getWideReg(&registers, instruction_args[0].register);

                    switch (instruction_args[1]) {
                        .immediate => {
                            if (std.mem.eql(u8, opcode.name, "mov")) {
                                target_reg.* = @bitCast(instruction_args[1].immediate.value);
                            } else if (std.mem.eql(u8, opcode.name, "add")) {
                                target_reg.* = target_reg.* +% @as(u16, @bitCast(instruction_args[1].immediate.value));
                                flags.update(target_reg.*);
                            } else if (std.mem.eql(u8, opcode.name, "cmp")) {
                                flags.update(
                                    target_reg.* -% @as(u16, @bitCast(instruction_args[1].immediate.value)),
                                );
                            } else if (std.mem.eql(u8, opcode.name, "sub")) {
                                target_reg.* = target_reg.* -% @as(u16, @bitCast(instruction_args[1].immediate.value));
                                flags.update(target_reg.*);
                            }
                        },
                        .register => {
                            const source_reg = reg.getWideReg(&registers, instruction_args[1].register);
                            if (std.mem.eql(u8, opcode.name, "mov")) {
                                target_reg.* = source_reg.*;
                            } else if (std.mem.eql(u8, opcode.name, "add")) {
                                target_reg.* = target_reg.* +% source_reg.*;
                                flags.update(target_reg.*);
                            } else if (std.mem.eql(u8, opcode.name, "cmp")) {
                                flags.update(target_reg.* -% source_reg.*);
                            } else if (std.mem.eql(u8, opcode.name, "sub")) {
                                target_reg.* = target_reg.* -% source_reg.*;
                                flags.update(target_reg.*);
                            }
                        },
                        .absolute_address => {
                            const source_address = instruction_args[1].absolute_address;
                            if (std.mem.eql(u8, opcode.name, "mov")) {
                                // TODO: assumes wide
                                const slice_size = 2; // cuz wide
                                const source_end = source_address + slice_size;
                                const slice = memory.sliceMemory(emu_mem, source_address, source_end);
                                const val_from_mem = std.mem.readInt(
                                    u16,
                                    slice[0..slice_size],
                                    .little,
                                );
                                target_reg.* = val_from_mem;
                            } else {
                                std.debug.print(
                                    "unhandled mnemonic {s} register, absolute_address: \n",
                                    .{opcode.name},
                                );
                            }
                        },
                        else => {
                            std.debug.print("unhandled second instruction argument: {s}\n", .{@tagName(instruction_args[1])});
                        },
                    }
                },
                .relative_address => {
                    if (std.mem.eql(u8, opcode.name, "jnz")) {
                        if (!flags.Z) {
                            if (instruction_args[0].relative_address < 0 and
                                @as(u16, @intCast(-instruction_args[0].relative_address)) > instruction_pointer)
                            {
                                @panic("Negative jump exceeded bounds");
                            } else {
                                instruction_pointer = @as(u16, @intCast(
                                    @as(i32, @intCast(instruction_pointer)) + instruction_args[0].relative_address,
                                ));
                            }
                        }
                    } else {
                        std.debug.print("unhandled mnemonic for relative address: {s}\n", .{opcode.name});
                    }
                },
                .absolute_address => {
                    const target_address = instruction_args[0].absolute_address;
                    switch (instruction_args[1]) {
                        .immediate => {
                            const immediate = instruction_args[1].immediate;
                            if (std.mem.eql(u8, opcode.name, "mov")) {
                                switch (immediate.size) {
                                    .byte => {
                                        unreachable; // narrow not supported
                                        // emu_mem.bytes[target_address] = @intCast(
                                        //     immediate.value,
                                        // );
                                    },
                                    .word => {
                                        const slice_size = 2; // cuz wide
                                        const target_slice = memory.sliceMemory(
                                            emu_mem,
                                            target_address,
                                            target_address + slice_size,
                                        );
                                        std.mem.writeInt(
                                            u16,
                                            target_slice[0..slice_size],
                                            @bitCast(immediate.value),
                                            .little,
                                        );
                                    },
                                    .registerDefined => unreachable,
                                }
                            } else {
                                std.debug.print("unhandled mnemonic for absolute_address, immediate: {s}\n", .{opcode.name});
                            }
                        },
                        else => {
                            std.debug.print("unhandled second operand for absolute_address: {}\n", .{instruction_args[1]});
                        },
                    }
                },
                .effective_address => {
                    const target_address = registers.calculateEffectiveAddress(
                        instruction_args[0].effective_address,
                    );
                    switch (instruction_args[1]) {
                        .immediate => {
                            const immediate = instruction_args[1].immediate;
                            if (std.mem.eql(u8, opcode.name, "mov")) {
                                // TODO Duplication with absolute address
                                switch (immediate.size) {
                                    .byte => {
                                        unreachable; // narrow not supported
                                    },
                                    .word => {
                                        const slice_size = 2; // cuz wide
                                        const target_slice = memory.sliceMemory(
                                            emu_mem,
                                            target_address,
                                            target_address + slice_size,
                                        );
                                        std.mem.writeInt(
                                            u16,
                                            target_slice[0..slice_size],
                                            @bitCast(immediate.value),
                                            .little,
                                        );
                                    },
                                    .registerDefined => unreachable,
                                }
                            } else {
                                std.debug.print("unhandled mnemonic for effective_address, immediate: {s}\n", .{opcode.name});
                            }
                        },
                        else => {
                            std.debug.print("unhandled second operand for effective_address: {}\n", .{instruction_args[1]});
                        },
                    }
                },
                else => {
                    std.debug.print("unhandled instruction argument: {s}\n", .{@tagName(instruction_args[0])});
                },
            }
            try stdout.print(" ; ", .{});
            try registers.print_changes(initial_registers, stdout);
            try stdout.print("ip:0x{x}->0x{x}", .{ initial_ip, instruction_pointer });
            if (!std.meta.eql(initial_flags, flags)) {
                try stdout.print(" flags:", .{});
                try initial_flags.print(stdout);
                try stdout.print("->", .{});
                try flags.print(stdout);
            }
        }

        try stdout.print("\n", .{});
    }

    if (parsed_args.execute) {
        try stdout.print("Final registers:\n", .{});
        try registers.print(stdout);
        try stdout.print("      ip: 0x{x:0>4} ({d})\n", .{ instruction_pointer, instruction_pointer });
        try stdout.print("   flags: ", .{});
        try flags.print(stdout);
    }
    try bw.flush();
}

const ParsedArgs = struct { file_path: []const u8, execute: bool };
const ArgumentErrors = error{InvalidArgument};

fn parseArgs(args: []const []const u8) !ParsedArgs {
    if (args.len == 3) {
        if (std.mem.eql(u8, args[1], "--execute")) {
            return .{
                .file_path = args[2],
                .execute = true,
            };
        } else {
            return ArgumentErrors.InvalidArgument;
        }
    } else if (args.len == 2) {
        return .{
            .file_path = args[1],
            .execute = false,
        };
    } else {
        return ArgumentErrors.InvalidArgument;
    }
}

fn decodeOpcodeAtAddress(mem: *memory.Memory, start_addr: u32, limit_addr: u32) !opcodes.DecodedOpcode {
    var opcode_length: u3 = 0;
    return while (opcode_length < opcodes.MAX_OPCODE_LENGTH) {
        opcode_length += 1;
        const opcode_end = start_addr + opcode_length;
        if (opcode_end <= limit_addr) {
            const opcode_bytes = memory.sliceMemory(mem, start_addr, opcode_end);
            assert(opcode_bytes.len > 0);
            assert(opcode_bytes.len <= opcodes.MAX_OPCODE_LENGTH);

            break opcodes.decodeOpcode(opcode_bytes) catch |err| switch (err) {
                opcodes.Errors.InsufficientBytes => {
                    // loop to get more bytes
                    continue;
                },
                else => err,
            };
        } else {
            return InvalidBinaryErrors.IncompleteInstruction;
        }
    } else unreachable;
}

test "decodeOpcodeAtAddress - given valid 1-byte instruction address returns opcode" {
    const allocator = std.testing.allocator;
    const mem = try allocator.create(memory.Memory);
    defer _ = allocator.destroy(mem);

    mem.bytes[0] = 0b1011_0000; // MOV immediate to register

    const result = try decodeOpcodeAtAddress(mem, 0, 1);

    try std.testing.expectEqual(result.id, opcodes.OpcodeId.movImmediateToReg);
}

test "decodeOpcodeAtAddress - given valid 2-byte instruction address at limit address it returns opcode" {
    const allocator = std.testing.allocator;
    const mem = try allocator.create(memory.Memory);
    defer _ = allocator.destroy(mem);

    mem.bytes[0] = 0b0000_0000; // Add register to mem or register
    mem.bytes[1] = 0b0011_0000;

    const result = try decodeOpcodeAtAddress(mem, 0, 2);

    try std.testing.expectEqual(result.id, opcodes.OpcodeId.addRegOrMemToEither);
}

test "decodeOpcodeAtAddress - given valid 2-byte instruction address not at limit it returns opcode" {
    const allocator = std.testing.allocator;
    const mem = try allocator.create(memory.Memory);
    defer _ = allocator.destroy(mem);

    mem.bytes[0] = 0b0000_0000; // Add register to mem or register
    mem.bytes[1] = 0b0011_0000;

    const result = try decodeOpcodeAtAddress(mem, 0, 200);

    try std.testing.expectEqual(result.id, opcodes.OpcodeId.addRegOrMemToEither);
}

test "decodeOpcodeAtAddress - unknown opcode returns error" {
    const allocator = std.testing.allocator;
    const mem = try allocator.create(memory.Memory);
    defer _ = allocator.destroy(mem);

    mem.bytes[0] = 0b1111_1111; // Not a valid instruction
    mem.bytes[1] = 0b1111_1111;

    const result = decodeOpcodeAtAddress(mem, 0, 2);

    try std.testing.expectError(opcodes.Errors.UnrecognisedOpcode, result);
}

test "decodeOpcodeAtAddress - an incomplete instruction it returns error" {
    const allocator = std.testing.allocator;
    const mem = try allocator.create(memory.Memory);
    defer _ = allocator.destroy(mem);

    mem.bytes[0] = 0b0000_0000; // Add register to mem or register

    const result = decodeOpcodeAtAddress(mem, 0, 1);

    try std.testing.expectError(InvalidBinaryErrors.IncompleteInstruction, result);
}

test {
    _ = std.testing.refAllDecls(@This());
}
