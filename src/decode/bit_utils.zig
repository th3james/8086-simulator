pub fn concat_u8_to_u16(array: [2]u8) u16 {
    return @as(u16, array[0]) << 8 | @as(u16, array[1]);
}
