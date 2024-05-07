const std = @import("std");

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <file_path>\n", .{args[0]});
        std.os.exit(1);
    }

    const file_path = args[1];

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("; {s} disassembly\n", .{file_path});
    try stdout.print("bits 16\n", .{});

    var buffer: [2]u8 = undefined;

    while (true) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read == 0) break;
        const instruction = decodeInstruction(buffer);
        try stdout.print("{s}", .{instruction.operation});
    }
    try stdout.print("\n", .{});

    try bw.flush();
}

const Instruction = struct {
    operation: []const u8,
};

fn decodeInstruction(inst: [2]u8) Instruction {
    _ = inst;
    return Instruction{
        .operation = "unknown",
    };
}

test "Unknown instruction decodes as unknown" {
    const result = decodeInstruction([_]u8{ 0b00000000, 0b00000000 });
    try std.testing.expectEqualStrings("unknown", result.operation);
}

test "MOV Decode" {
    const result = decodeInstruction([_]u8{ 0b10001000, 0b00000000 });
    try std.testing.expectEqualStrings("mov", result.operation);
}
