const std = @import("std");

const HttpProfile = struct {
    AESPSK: struct {
        value: []const u8,
        enc_key: []const u8,
        dec_key: []const u8,
    },
    callback_host: []const u8,
    callback_interval: u32,
    callback_jitter: u32,
    callback_port: u32,
    encrypted_exchange_check: bool,
    get_uri: []const u8,
    headers: std.json.ArrayHashMap([]const u8),
    post_uri: []const u8,
};

pub fn main() !void {
    const json_str =
        \\{"AESPSK":{"value":"aes256_hmac","enc_key":"KaYvsx1E4IjGIR71pwCEbnsiwczmdCBmXwlZE69ogkM=","dec_key":"KaYvsx1E4IjGIR71pwCEbnsiwczmdCBmXwlZE69ogkM="},"callback_host":"http://169.254.51.218","callback_interval":10,"callback_jitter":23,"callback_port":80,"encrypted_exchange_check":true,"get_uri":"index","headers":{"User-Agent":"Mozilla/5.0 (Windows NT 6.3; Trident/7.0; rv:11.0) like Gecko"},"post_uri":"data"}
    ;

    const smp_alloc = std.heap.smp_allocator;
    //const decoder = std.base64.Base64Decoder.init(std.base64.standard_alphabet_chars, '=');
    //const b64_json: []const u8 = std.mem.span(std.os.argv[1]);
    //const decoded_size = try decoder.calcSizeForSlice(b64_json);

    //var buf: [1024]u8 = undefined;
    //var json = buf[0..decoded_size];
    //try decoder.decode(json[0..], b64_json);

    //const deseralized = try std.json.parseFromSlice(HttpProfile, smp_alloc, json, .{});
    //defer deseralized.deinit();

    //std.debug.print("Url: {s}\n", .{deseralized.value.Url});

    //for (deseralized.value.Headers.map.keys(), deseralized.value.Headers.map.values()) |key, value| {
    //    std.debug.print("\t{s} : {s}\n", .{ key, value });
    //}

    const deseralized = try std.json.parseFromSlice(HttpProfile, smp_alloc, json_str, .{});
    defer deseralized.deinit();
    const http_profile = deseralized.value;

    var out = std.io.Writer.Allocating.init(smp_alloc);
    defer out.deinit();
    try std.json.Stringify.value(http_profile, .{}, &out.writer);
    std.debug.print("{s}\n", .{out.written()});
}
