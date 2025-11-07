const std = @import("std");

const HttpProfile = struct {
    Url: []const u8,
    Headers: std.json.ArrayHashMap([]const u8),
};

pub fn main() !void {
    const smp_alloc = std.heap.smp_allocator;
    const decoder = std.base64.Base64Decoder.init(std.base64.standard_alphabet_chars, '=');
    const b64_json: []const u8 = std.mem.span(std.os.argv[1]);
    const decoded_size = try decoder.calcSizeForSlice(b64_json);

    var buf: [1024]u8 = undefined;
    var json = buf[0..decoded_size];
    try decoder.decode(json[0..], b64_json);

    const deseralized = try std.json.parseFromSlice(HttpProfile, smp_alloc, json, .{});
    defer deseralized.deinit();

    std.debug.print("Url: {s}\n", .{deseralized.value.Url});

    for (deseralized.value.Headers.map.keys(), deseralized.value.Headers.map.values()) |key, value| {
        std.debug.print("\t{s} : {s}\n", .{ key, value });
    }
}
