const std = @import("std");
const assert = std.debug.assert;
const decode = @import("decode/core.zig");
const opcode_masks = @import("decode/opcode_masks.zig");
const memory = @import("memory.zig");

const InvalidBinaryErrors = error{ IncompleteInstruction, MissingDisplacementError };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <file_path>\n", .{args[0]});
        std.process.exit(1);
    }

    const file_path = args[1];

    const emu_mem = try allocator.create(memory.Memory);
    defer _ = allocator.destroy(emu_mem);

    const program_len = try memory.loadFromFile(file_path, emu_mem);
    assert(program_len > 0);

    try disassemble(&allocator, emu_mem, program_len);
}

fn decodeOpcodeAtAddress(mem: *memory.Memory, start_addr: u32, limit_addr: u32) !opcode_masks.DecodedOpcode {
    const MAX_OPCODE_LENGTH = 2;
    var opcode_length: u3 = 1;
    return while (opcode_length <= MAX_OPCODE_LENGTH) {
        const opcode_end = start_addr + opcode_length;
        if (opcode_end <= limit_addr) {
            const opcode_bytes = memory.sliceMemory(&mem, start_addr, opcode_end);
            assert(opcode_bytes.len > 0);
            assert(opcode_bytes.len <= MAX_OPCODE_LENGTH);

            // if this errors, loop to read more bytes
            const result = decode.decodeOpcode(opcode_bytes) catch |err| switch (err) {
                decode.Errors.InsufficientBytes => {
                    opcode_length += 1;
                    continue;
                },
            };

            break result;
        } else {
            return InvalidBinaryErrors.IncompleteInstruction;
        }
    } else unreachable;
}

fn disassemble(allocator: *std.mem.Allocator, mem: *memory.Memory, program_len: u32) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("bits 16\n", .{});

    var arena = std.heap.ArenaAllocator.init(allocator.*);
    defer arena.deinit();

    var memory_address: u32 = 0;
    while (memory_address < program_len) {
        _ = arena.reset(.retain_capacity);
        const arena_allocator = arena.allocator();

        const opcode = try decodeOpcodeAtAddress(mem, memory_address, program_len);

        const data_map = decode.getInstructionDataMap(opcode);
        const full_instruction_length = decode.getInstructionLength(data_map);

        const instruction_end = memory_address + @max(
            opcode.length,
            full_instruction_length,
        );
        assert(instruction_end > memory_address);
        const instruction_bytes = if (instruction_end <= program_len)
            memory.sliceMemory(&mem, memory_address, instruction_end)
        else
            return InvalidBinaryErrors.IncompleteInstruction;
        assert((instruction_end - memory_address) > 0);
        assert((instruction_end - memory_address) <= 6);
        memory_address = instruction_end;

        const raw_instruction = decode.RawInstruction{
            .base = instruction_bytes,
            .opcode = opcode,
            .data_map = data_map,
        };

        if (false) { //raw_instruction.opcode.id == .cmpImmediateToRegOrMem) {
            std.debug.print("Input {b}\n", .{raw_instruction.base});
            std.debug.print("\t{any}\n", .{raw_instruction.opcode});
            std.debug.print("\t{any}\n", .{raw_instruction.data_map});
        }

        const instruction_args = try decode.decodeArgs(arena_allocator, raw_instruction);

        const args_str = try std.mem.join(arena_allocator, ", ", instruction_args.args);
        // std.debug.print("Result: {s} {s}\n", .{ opcode.name, args_str });
        try stdout.print("{s} {s}\n", .{ opcode.name, args_str });
    }

    try bw.flush();
}
