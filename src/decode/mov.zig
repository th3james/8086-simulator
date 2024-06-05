// TODO deprecate these in favour of OptionOptions
const REG_DESTINATION_MASK: u8 = 0b00000010;
pub fn regIsDestination(instruction: [2]u8) bool {
    return (instruction[0] & REG_DESTINATION_MASK) != 0;
}
