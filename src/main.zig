const std = @import("std");
const decode = @import("decode/core.zig");

const InvalidBinaryErrors = error{MissingDisplacementError};

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <file_path>\n", .{args[0]});
        std.process.exit(1);
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

        const opcode = decode.decodeOpcode(buffer);
        var displacement: [2]u8 = .{ 0, 0 };
        switch (opcode.displacement_size) {
            decode.DisplacementSize.wide => {
                const further_bytes_read = try file.read(&displacement);
                if (further_bytes_read == 0) return InvalidBinaryErrors.MissingDisplacementError;
            },
            decode.DisplacementSize.narrow => {
                var narrow_buffer: [1]u8 = undefined;
                const further_bytes_read = try file.read(&narrow_buffer);
                if (further_bytes_read == 0) return InvalidBinaryErrors.MissingDisplacementError;
                displacement[0] = narrow_buffer[0];
            },
            else => {},
        }

        const instruction = try decode.decodeInstruction(opcode, displacement);
        defer instruction.deinit(&std.heap.page_allocator);

        const args_str = try std.mem.join(std.heap.page_allocator, ", ", instruction.args);
        defer std.heap.page_allocator.free(args_str);
        try stdout.print("{s} {s}\n", .{ opcode.name, args_str });
    }

    try bw.flush();
}
