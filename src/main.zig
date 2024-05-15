const std = @import("std");

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
        const instruction = try decodeInstruction(buffer);
        defer instruction.deinit(&std.heap.page_allocator);
        const args_str = try std.mem.join(std.heap.page_allocator, ", ", instruction.args);
        defer std.heap.page_allocator.free(args_str);
        try stdout.print("{s} {s}\n", .{ instruction.operation, args_str });
    }

    try bw.flush();
}

const Instruction = struct {
    operation: []const u8,
    args: []const []const u8,

    fn deinit(self: *const Instruction, allocator: *const std.mem.Allocator) void {
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
    }
};

fn decodeInstruction(inst: [2]u8) !Instruction {
    // TODO convert bit masks to defines
    const opcode = inst[0] & 0b11111100;
    var args = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer args.deinit();

    switch (opcode) {
        0b10001000 => {
            std.debug.print("\n# Decoding Mov {b}, {b}\n", .{ inst[0], inst[1] });
            const regIsDestination = (inst[0] & 0b00000010) != 0;
            const wide = (inst[0] & 0b00000001) != 0;
            std.debug.print("\twide: {}, ", .{wide});
            const mod = inst[1] & 0b11000000;
            _ = mod;
            const regToReg = (inst[1] & 0b11000000) == 192;
            const reg = (inst[1] & 0b00111000) >> 3;
            std.debug.print("\treg: {b}\n", .{reg});
            const regOrMem = inst[1] & 0b00000111;

            if (regToReg) {
                if (regIsDestination) {
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(reg, wide)));
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(regOrMem, wide)));
                } else {
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(regOrMem, wide)));
                    try args.append(try std.heap.page_allocator.dupe(u8, registerName(reg, wide)));
                }
            } else {
                try args.append(try std.heap.page_allocator.dupe(u8, "unsupported"));
            }
            return Instruction{ .operation = "mov", .args = try args.toOwnedSlice() };
        },
        else => {
            return Instruction{ .operation = "unknown", .args = try args.toOwnedSlice() };
        },
    }
}

const RegisterName = struct {
    narrow: []const u8,
    wide: []const u8,
};
const registerMap = [_]RegisterName{
    RegisterName{ .narrow = "al", .wide = "ax" },
    RegisterName{ .narrow = "cl", .wide = "cx" },
    RegisterName{ .narrow = "dl", .wide = "dx" },
    RegisterName{ .narrow = "bl", .wide = "bx" },
    RegisterName{ .narrow = "ah", .wide = "sp" },
    RegisterName{ .narrow = "ch", .wide = "bp" },
    RegisterName{ .narrow = "dh", .wide = "si" },
    RegisterName{ .narrow = "bh", .wide = "di" },
};

fn registerName(reg: u8, wide: bool) []const u8 {
    if (reg >= registerMap.len) {
        return "xx"; // Unknown or invalid register code
    }

    const names = registerMap[reg];
    return if (wide) names.wide else names.narrow;
}

test "Unknown instruction decodes as unknown" {
    const result = try decodeInstruction([_]u8{ 0b00000000, 0b00000000 });
    defer result.deinit(&std.heap.page_allocator);
    try std.testing.expectEqualStrings("unknown", result.operation);
}

test "MOV Decode - operation" {
    const result = try decodeInstruction([_]u8{ 0b10001000, 0b00000000 });
    defer result.deinit(&std.heap.page_allocator);
    try std.testing.expectEqualStrings("mov", result.operation);
}

test "MOV Decode - Reg to Reg only" {
    const unsupported = try decodeInstruction([_]u8{ 0b10001000, 0b00000000 });
    defer unsupported.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 1), unsupported.args.len);
    try std.testing.expectEqualStrings("unsupported", unsupported.args[0]);
}

test "MOV Decode - Reg to Reg permutations" {
    const unsupported = try decodeInstruction([_]u8{ 0b10001000, 0b11000001 });
    defer unsupported.deinit(&std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 2), unsupported.args.len);
    try std.testing.expectEqualStrings(registerName(0b1, false), unsupported.args[0]);
    try std.testing.expectEqualStrings(registerName(0b0, false), unsupported.args[1]);
}

test "registerName options" {
    try std.testing.expectEqualStrings("al", registerName(0b000, false));
    try std.testing.expectEqualStrings("cx", registerName(0b001, true));
}
