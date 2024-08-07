pub const OpcodeId = enum {
    movRegOrMemToFromReg,
    addRegOrMemToEither,
    subRegOrMemToEither,
    cmpRegOrMemToReg,
    movImmediateToReg,
    movImmediateToRegOrMem,
    addImmediateToRegOrMem,
    subImmediateToRegOrMem,
    cmpImmediateToRegOrMem,
    memoryToAccumulator,
    accumulatorToMemory,
    addImmediateToAccumulator,
    subImmediateToAccumulator,
    cmpImmediateWithAccumulator,
    jmpIfZero,
    jmpIfNotZero,
    jmpIfLess,
    jmpIfLessOrEq,
    jmpIfBelow,
    jmpIfBelowOrEq,
    jmpIfParity,
    jmpOnOverflow,
    jmpOnSign,
    jmpIfGreater,
    jmpIfGreaterOrEq,
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
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.addRegOrMemToEither,
        .name = "add",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b0000_0000_0000_0000,
        .bytes_required = 2,
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.subRegOrMemToEither,
        .name = "sub",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b0010_1000_0000_0000,
        .bytes_required = 2,
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.cmpRegOrMemToReg,
        .name = "cmp",
        .identifier_mask = 0b1111_1100_0000_0000,
        .identifier = 0b0011_1000_0000_0000,
        .bytes_required = 2,
        .regIsDestination = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .reg = .{ .mask = 0b0000_0000_0011_1000, .shift = 3 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.movImmediateToRegOrMem,
        .name = "mov",
        .identifier_mask = 0b1111_1110_0011_1000,
        .identifier = 0b1100_0110_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
    },
    .{
        .id = OpcodeId.addImmediateToRegOrMem,
        .name = "add",
        .identifier_mask = 0b1111_1100_0011_1000,
        .identifier = 0b1000_0000_0000_0000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
        .sign = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
    },
    .{
        .id = OpcodeId.subImmediateToRegOrMem,
        .name = "sub",
        .identifier_mask = 0b1111_1100_0011_1000,
        .identifier = 0b1000_0000_0010_1000,
        .bytes_required = 2,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
        .sign = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
    },
    .{
        .id = OpcodeId.cmpImmediateToRegOrMem,
        .name = "cmp",
        .identifier_mask = 0b1111_1100_0011_1000,
        .identifier = 0b1000_0000_0011_1000,
        .bytes_required = 2,
        .sign = .{ .mask = 0b0000_0010_0000_0000, .shift = 9 },
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
        .mod = .{ .mask = 0b0000_0000_1100_0000, .shift = 6 },
        .regOrMem = .{ .mask = 0b0000_0000_0000_0111, .shift = 0 },
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
    .{
        .id = OpcodeId.subImmediateToAccumulator,
        .name = "sub",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b0010_1100_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.cmpImmediateWithAccumulator,
        .name = "cmp",
        .identifier_mask = 0b1111_1110_0000_0000,
        .identifier = 0b0011_1100_0000_0000,
        .bytes_required = 1,
        .wide = .{ .mask = 0b0000_0001_0000_0000, .shift = 8 },
    },
    .{
        .id = OpcodeId.jmpIfZero,
        .name = "je",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0100_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfLess,
        .name = "jl",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1100_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfLessOrEq,
        .name = "jle",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1110_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfBelow,
        .name = "jb",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0010_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = OpcodeId.jmpIfBelowOrEq,
        .name = "jbe",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0110_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfNotZero,
        .name = "jnz",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0101_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfParity,
        .name = "jp",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1010_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpOnOverflow,
        .name = "jo",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_0000_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpOnSign,
        .name = "js",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1000_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfGreater,
        .name = "jg",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1111_0000_0000,
        .bytes_required = 1,
    },
    .{
        .id = .jmpIfGreaterOrEq,
        .name = "jge",
        .identifier_mask = 0b1111_1111_0000_0000,
        .identifier = 0b0111_1101_0000_0000,
        .bytes_required = 1,
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
