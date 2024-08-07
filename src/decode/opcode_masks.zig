pub const OpcodeId = enum {
    movRegOrMemToFromReg,
    addRegOrMemToEither,
    movImmediateToReg,
    movImmediateToRegOrMem,
    addImmediateToRegOrMem,
    memoryToAccumulator,
    accumulatorToMemory,
    addImmediateToAccumulator,
    unknown,
};

pub const FieldDefinition = struct {
    mask: u16,
    shift: u4,
};

pub const OpcodeDefinition = struct {
    id: OpcodeId,
    name: []const u8,
    identifier_mask: u16,
    identifier: u16,
    bytes_required: u2,
    wide: ?FieldDefinition = null,
    sign: ?FieldDefinition = null,
    mod: ?FieldDefinition = null,
    reg: ?FieldDefinition = null,
    regOrMem: ?FieldDefinition = null,
    regIsDestination: ?FieldDefinition = null,
};

pub const DecodedOpcode = struct {
    id: OpcodeId,
    name: []const u8,
    wide: ?bool = null,
    sign: bool = false,
    mod: ?u2 = null,
    reg: ?u3 = null,
    regOrMem: ?u3 = null,
    regIsDestination: ?bool = null,
};

pub const UnknownOpcode = DecodedOpcode{
    .id = OpcodeId.unknown,
    .name = "???",
};

pub const OpcodeTable = [_]OpcodeDefinition{
    .{
        .id = OpcodeId.movRegOrMemToFromReg,
        .name = "mov",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b1000_1000_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
    },
    .{
        .id = OpcodeId.addRegOrMemToEither,
        .name = "add",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b0000_0000_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
    },
    .{
        .id = OpcodeId.movImmediateToRegOrMem,
        .name = "mov",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b1100_0110_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.addImmediateToRegOrMem,
        .name = "add",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b1000_0000_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
        .sign = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
    },
    .{
        .id = OpcodeId.movImmediateToReg,
        .name = "mov",
        .identifier_mask = 0b1111_0000_0000_0000,
        .identifier = 0b1011_0000_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_1000_0000_0000, .shift = 11 },
        .reg = .{ .mask = 0b0000_0111_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.memoryToAccumulator,
        .name = "mov",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b1010_0000_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.accumulatorToMemory,
        .name = "mov",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b1010_0010_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.addImmediateToAccumulator,
        .name = "add",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b0000_0100_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
};

pub const InstructionField = struct {
    start: u4,
    end: u4,
};

pub const InstructionDataMap = struct {
    displacement: ?InstructionField = null,
    data: ?InstructionField = null,
};
