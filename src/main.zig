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
    var memory_address: u32 = 0;
    while (memory_address < program_len) {
        _ = arena.reset(.retain_capacity);
        const arena_allocator = arena.allocator();

        // Decode
        const opcode = try decodeOpcodeAtAddress(emu_mem, memory_address, program_len);

        const layout = instruction_layout.getInstructionLayout(opcode);

        const instruction_end = memory_address + instruction_layout.getInstructionLength(opcode.length, layout);
        assert(instruction_end > memory_address);
        assert((instruction_end - memory_address) <= instruction_layout.MAX_INSTRUCTION_LENGTH);

        const instruction_bytes = if (instruction_end <= program_len)
            memory.sliceMemory(emu_mem, memory_address, instruction_end)
        else
            // TODO handle this error
            return InvalidBinaryErrors.IncompleteInstruction;
        memory_address = instruction_end;

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
            if (std.mem.eql(u8, opcode.name, "mov")) {
                if (instruction_args[0] == .register) {
                    if (instruction_args[1] == .immediate) {
                        const source_reg = reg.getWideReg(&registers, instruction_args[0].register);
                        const current_val = source_reg.*;
                        const new_value = instruction_args[1].immediate.value;
                        try stdout.print(" ; {s}:0x{x}->0x{x}", .{
                            @tagName(instruction_args[0].register),
                            current_val,
                            new_value,
                        });
                    }
                }
            }
        }

        try stdout.print("\n", .{});
    }

    if (parsed_args.execute) {
        try stdout.print("Final registers:", .{});
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
