// TODO deprecate these in favour of OptionOptions
const REG_DESTINATION_MASK: u8 = 0b00000010;
pub fn regIsDestination(instruction: [2]u8) bool {
    return (instruction[0] & REG_DESTINATION_MASK) != 0;
}

const MOD_MASK: u8 = 0b11000000;
pub fn mod(instruction: [2]u8) u2 {
    return @intCast((instruction[1] & MOD_MASK) >> 6);
}

const REG_OR_MEM_MASK: u8 = 0b00000111;
pub fn regOrMem(instruction: [2]u8) u3 {
    return @intCast(instruction[1] & REG_OR_MEM_MASK);
}
