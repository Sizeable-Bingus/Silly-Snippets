const std = @import("std");

fn indirection(decoder: std.base64.Base64Decoder, b64_string: []const u8, len: usize, buf: []u8) !void {
    try decoder.decode(buf[0..len], b64_string);
    std.debug.print("[PARAM] {s}\n", .{buf[0..len]});
}

fn decode_param(decoder: std.base64.Base64Decoder, b64_string: []const u8) !void {
    var buf: [256]u8 = undefined;
    const decode_len = try decoder.calcSizeForSlice(b64_string);
    try indirection(decoder, b64_string, decode_len, &buf);
}

pub fn main() !void {
    try decode_param(std.base64.Base64Decoder.init(std.base64.standard_alphabet_chars, '='), "YmluZ3Vz");
}
