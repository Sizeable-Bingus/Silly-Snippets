const std = @import("std");

fn mythicFormatStruct(allocator: std.mem.Allocator, in_struct: anytype) ![]const u8 {
    var out = std.io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(in_struct, .{}, &out.writer);
    const json = out.written();

    const encoder = std.base64.Base64Encoder.init(std.base64.standard_alphabet_chars, '=');
    const b64_output_size = encoder.calcSize(json.len);
    const b64_buf = try allocator.alloc(u8, b64_output_size);
    errdefer allocator.free(b64_buf);
    return encoder.encode(b64_buf, json);
}

pub fn main() !void {
    const data = try mythicFormatStruct(std.heap.smp_allocator, .{ .a = 1, .b = 2, .bingus = "data" });
    defer std.heap.smp_allocator.free(data);
    std.debug.print("{s}\n", .{data});
}
