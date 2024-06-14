const std = @import("std");
const decode = @import("decode/core.zig");

const InvalidBinaryErrors = error{MissingDisplacementError};

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

    try disassembleFile(file_path, &allocator);
}

fn disassembleFile(file_path: []const u8, allocator: *std.mem.Allocator) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

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

        const instruction = try decode.decodeInstruction(opcode, displacement, allocator);
        defer instruction.deinit(allocator);

        const args_str = try std.mem.join(allocator.*, ", ", instruction.args);
        defer allocator.free(args_str);
        try stdout.print("{s} {s}\n", .{ opcode.name, args_str });
    }

    try bw.flush();
}
