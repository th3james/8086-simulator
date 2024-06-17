pub const OpcodeId = enum {
    movRegOrMemToFromReg,
    movImmediateToReg,
    movImmediateToRegOrMem,
    unknown,
};

const OpcodeMask = struct {
    identifier_mask: u8,
    identifier: u8,
    id: OpcodeId,
};

pub const OpcodeOptions = struct {
    wide: bool,
    mod: u2,
    reg: u3,
    regOrMem: u3,
};

pub fn parseOptions(id: OpcodeId, instruction: [2]u8) OpcodeOptions {
    switch (id) {
        OpcodeId.movRegOrMemToFromReg => {
            return OpcodeOptions{
                .wide = (instruction[0] & 0b00000001) != 0,
                .mod = @intCast((instruction[1] & 0b11000000) >> 6),
                .reg = @intCast((instruction[1] & 0b00111000) >> 3),
                .regOrMem = @intCast(instruction[1] & 0b00000111),
            };
        },
        OpcodeId.movImmediateToRegOrMem => {
            return OpcodeOptions{
                .wide = false, // TODO
                .mod = 0, // TODO
                .reg = 0, // TODO
                .regOrMem = 0, // TODO
            };
        },
        OpcodeId.movImmediateToReg => {
            return OpcodeOptions{
                .wide = (instruction[0] & 0b00001000) != 0,
                .mod = 0, // TODO
                .reg = @intCast(instruction[0] & 0b00000111),
                .regOrMem = 0, // TODO
            };
        },
        OpcodeId.unknown => {
            return OpcodeOptions{
                .wide = false,
                .mod = 0,
                .reg = 0,
                .regOrMem = 0,
            };
        },
    }
}

pub const OpcodeTable = [_]OpcodeMask{
    OpcodeMask{
        .id = OpcodeId.movRegOrMemToFromReg,
        .identifier_mask = 0b11111100,
        .identifier = 0b10001000,
    },
    OpcodeMask{
        .id = OpcodeId.movImmediateToRegOrMem,
        .identifier_mask = 0b11111110,
        .identifier = 0b11000110,
    },
    OpcodeMask{
        .id = OpcodeId.movImmediateToReg,
        .identifier_mask = 0b11110000,
        .identifier = 0b10110000,
    },
};
