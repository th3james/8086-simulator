const std = @import("std");
const decode = @import("decode/core.zig");

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

    try disassembleFile(&allocator, file_path);
}

fn disassembleFile(allocator: *std.mem.Allocator, file_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("; {s} disassembly\n", .{file_path});
    try stdout.print("bits 16\n", .{});

    var arena = std.heap.ArenaAllocator.init(allocator.*);
    defer arena.deinit();

    const MAX_INSTRUCTION_SIZE = 6;
    const MAX_OPCODE_LENGTH = 2;
    var buffer: [1]u8 = undefined;

    while (true) {
        _ = arena.reset(.retain_capacity);
        const arena_allocator = arena.allocator();

        var instruction_bytes: [MAX_INSTRUCTION_SIZE]u8 = [_]u8{0} ** MAX_INSTRUCTION_SIZE;

        var opcode_length: u3 = 0;

        while (opcode_length < MAX_OPCODE_LENGTH) {
            const bytes_read = try file.read(&buffer);
            if (bytes_read == 0) {
                if (opcode_length == 0) {
                    break;
                } else {
                    return InvalidBinaryErrors.IncompleteInstruction;
                }
            }

            instruction_bytes[opcode_length] = buffer[0];
            opcode_length += 1;

            // if this errors, loop to read more bytes
            _ = decode.decodeOpcode(instruction_bytes[0..opcode_length]) catch |err| switch (err) {
                decode.Errors.InsufficientBytes => {
                    continue;
                },
            };

            break; // decode must have succeeded
        }

        if (opcode_length == 0) {
            break; // EoF
        }

        const opcode = try decode.decodeOpcode(instruction_bytes[0..opcode_length]);
        const data_map = decode.getInstructionDataMap(opcode);
        const full_instruction_length = decode.getInstructionLength(data_map);

        while (opcode_length < full_instruction_length) {
            const bytes_read = try file.read(&buffer);
            if (bytes_read == 0) {
                if (opcode_length == 0) {
                    break; // end of file
                } else {
                    return InvalidBinaryErrors.IncompleteInstruction;
                }
            }
            instruction_bytes[opcode_length] = buffer[0];
            opcode_length += 1;
        }

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
