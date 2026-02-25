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
            domain_specific_headers: ?std.json.ArrayHashMap(std.json.ArrayHashMap([]const u8)) = null,
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
    errdefer allocator.free(transformed_data);
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

    if (!client) std.mem.reverse(Transform, transforms);
    for (transforms) |trans| {
        //std.debug.print("[Transform:GET] {s} : {s}\n", .{ trans.action, trans.value orelse "null" });
        const transform = std.meta.stringToEnum(TransformOperation, trans.action).?;
        switch (transform) {
            .base64 => {
                if (client) {
                    const len = encoder.calcSize(transformed_data.len);
                    const new_data_buf = try allocator.alloc(u8, len);
                    errdefer allocator.free(new_data_buf);
                    const new = encoder.encode(new_data_buf, transformed_data);
                    allocator.free(transformed_data);
                    transformed_data = new;
                } else {
                    const len = try decoder.calcSizeForSlice(transformed_data);
                    const new_data_buf = try allocator.alloc(u8, len);
                    errdefer allocator.free(new_data_buf);
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
                    errdefer allocator.free(new_data_buf);
                    const new = url_safe_encoder.encode(new_data_buf, transformed_data);
                    allocator.free(transformed_data);
                    transformed_data = new;
                } else {
                    const url_safe_decoder = std.base64.Base64Decoder.init(std.base64.url_safe_alphabet_chars, '=');
                    const len = try url_safe_decoder.calcSizeForSlice(transformed_data);
                    const new_data_buf = try allocator.alloc(u8, len);
                    errdefer allocator.free(new_data_buf);
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
                errdefer allocator.free(new);
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

    //const b64_profile = "eyJBRVNQU0siOnsidmFsdWUiOiJhZXMyNTZfaG1hYyIsImVuY19rZXkiOiJ3djM2OHkzMzR5K2NsVTNQYXA1TVo3RCt0Ti9PVTRJeGp1SWdUcUExbXNnPSIsImRlY19rZXkiOiJ3djM2OHkzMzR5K2NsVTNQYXA1TVo3RCt0Ti9PVTRJeGp1SWdUcUExbXNnPSJ9LCJjYWxsYmFja19kb21haW5zIjpbImh0dHA6Ly8xMC4yMzAuMTQ5LjgwIl0sImNhbGxiYWNrX2ludGVydmFsIjo1LCJjYWxsYmFja19qaXR0ZXIiOjIzLCJkb21haW5fcm90YXRpb24iOiJyb3VuZC1yb2JpbiIsImVuY3J5cHRlZF9leGNoYW5nZV9jaGVjayI6ZmFsc2UsImZhaWxvdmVyX3RocmVzaG9sZCI6NSwia2lsbGRhdGUiOiIyMDI3LTAyLTIzIiwicmF3X2MyX2NvbmZpZyI6ImV3b2dJQ0p1WVcxbElqb2dJbFJGVTFRaUxBb2dJQ0puWlhRaU9pQjdDaUFnSUNBaWRtVnlZaUk2SUNKSFJWUWlMQW9nSUNBZ0luVnlhWE1pT2lCYkNpQWdJQ0FnSUNJdmJYa3ZkWEpwTDNCaGRHZ2lDaUFnSUNCZExBb2dJQ0FnSW1Oc2FXVnVkQ0k2SUhzS0lDQWdJQ0FnSW1obFlXUmxjbk1pT2lCN0NpQWdJQ0FnSUNBZ0lsVnpaWEl0UVdkbGJuUWlPaUFpVFc5NmFXeHNZUzgxTGpBZ0tGZHBibVJ2ZDNNZ1RsUWdNVEF1TURzZ1YybHVOalE3SUhnMk5Da2dRWEJ3YkdWWFpXSkxhWFF2TlRNM0xqTTJJQ2hMU0ZSTlRDd2diR2xyWlNCSFpXTnJieWtnUTJoeWIyMWxMekV3TlM0d0xqQXVNQ0JUWVdaaGNta3ZOVE0zTGpNMklnb2dJQ0FnSUNCOUxBb2dJQ0FnSUNBaWNHRnlZVzFsZEdWeWN5STZJSHNLSUNBZ0lDQWdJQ0FpVFhsTFpYa2lPaUFpZG1Gc2RXVWlDaUFnSUNBZ0lIMHNDaUFnSUNBZ0lDSmtiMjFoYVc1ZmMzQmxZMmxtYVdOZmFHVmhaR1Z5Y3lJNklIc0tJQ0FnSUNBZ0lDQWlhSFIwY0hNNkx5OWxlR0Z0Y0d4bExtTnZiVG8wTkRNaU9pQjdDaUFnSUNBZ0lDQWdJQ0FpVlhObGNpMUJaMlZ1ZENJNklDSlVaWE4wSWdvZ0lDQWdJQ0FnSUgwS0lDQWdJQ0FnZlN3S0lDQWdJQ0FnSW0xbGMzTmhaMlVpT2lCN0NpQWdJQ0FnSUNBZ0lteHZZMkYwYVc5dUlqb2dJbU52YjJ0cFpTSXNDaUFnSUNBZ0lDQWdJbTVoYldVaU9pQWljMlZ6YzJsdmJrbEVJZ29nSUNBZ0lDQjlMQW9nSUNBZ0lDQWlkSEpoYm5ObWIzSnRjeUk2SUZzS0lDQWdJQ0FnSUNCN0NpQWdJQ0FnSUNBZ0lDQWlZV04wYVc5dUlqb2dJbUpoYzJVMk5IVnliQ0lLSUNBZ0lDQWdJQ0I5Q2lBZ0lDQWdJRjBLSUNBZ0lIMHNDaUFnSUNBaWMyVnlkbVZ5SWpvZ2V3b2dJQ0FnSUNBaWFHVmhaR1Z5Y3lJNklIc0tJQ0FnSUNBZ0lDQWlVMlZ5ZG1WeUlqb2dJbE5sY25abGNpSXNDaUFnSUNBZ0lDQWdJa05oWTJobExVTnZiblJ5YjJ3aU9pQWliV0Y0TFdGblpUMHdMQ0J1YnkxallXTm9aU0lLSUNBZ0lDQWdmU3dLSUNBZ0lDQWdJblJ5WVc1elptOXliWE1pT2lCYkNpQWdJQ0FnSUNBZ2V3b2dJQ0FnSUNBZ0lDQWdJbUZqZEdsdmJpSTZJQ0o0YjNJaUxBb2dJQ0FnSUNBZ0lDQWdJblpoYkhWbElqb2dJbXRsZVVobGNtVWlDaUFnSUNBZ0lDQWdmU3dLSUNBZ0lDQWdJQ0I3Q2lBZ0lDQWdJQ0FnSUNBaVlXTjBhVzl1SWpvZ0ltSmhjMlUyTkhWeWJDSUtJQ0FnSUNBZ0lDQjlMQW9nSUNBZ0lDQWdJSHNLSUNBZ0lDQWdJQ0FnSUNKaFkzUnBiMjRpT2lBaWNISmxjR1Z1WkNJc0NpQWdJQ0FnSUNBZ0lDQWlkbUZzZFdVaU9pQWllMXdpY21WemNHOXVjMlZjSWpwY0lpSUtJQ0FnSUNBZ0lDQjlMQW9nSUNBZ0lDQWdJSHNLSUNBZ0lDQWdJQ0FnSUNKaFkzUnBiMjRpT2lBaVlYQndaVzVrSWl3S0lDQWdJQ0FnSUNBZ0lDSjJZV3gxWlNJNklDSmNJbjBpQ2lBZ0lDQWdJQ0FnZlN3S0lDQWdJQ0FnSUNCN0NpQWdJQ0FnSUNBZ0lDQWlZV04wYVc5dUlqb2dJbTVsZEdKcGIzTWlDaUFnSUNBZ0lDQWdmUW9nSUNBZ0lDQmRDaUFnSUNCOUNpQWdmU3dLSUNBaWNHOXpkQ0k2SUhzS0lDQWdJQ0oxY21seklqb2dXd29nSUNBZ0lDQWlMMjE1TDI5MGFHVnlMM0JoZEdnaUNpQWdJQ0JkTEFvZ0lDQWdJblpsY21JaU9pQWlVRTlUVkNJc0NpQWdJQ0FpWTJ4cFpXNTBJam9nZXdvZ0lDQWdJQ0FpYUdWaFpHVnljeUk2SUhzS0lDQWdJQ0FnSUNBaVZYTmxjaTFCWjJWdWRDSTZJQ0pOYjNwcGJHeGhMelV1TUNBb1YybHVaRzkzY3lCT1ZDQXhNQzR3T3lCWGFXNDJORHNnZURZMEtTQkJjSEJzWlZkbFlrdHBkQzgxTXpjdU16WWdLRXRJVkUxTUxDQnNhV3RsSUVkbFkydHZLU0JEYUhKdmJXVXZNVEExTGpBdU1DNHdJRk5oWm1GeWFTODFNemN1TXpZaUNpQWdJQ0FnSUgwc0NpQWdJQ0FnSUNKMGNtRnVjMlp2Y20xeklqb2dXd29nSUNBZ0lDQWdJSHNLSUNBZ0lDQWdJQ0FnSUNKaFkzUnBiMjRpT2lBaWVHOXlJaXdLSUNBZ0lDQWdJQ0FnSUNKMllXeDFaU0k2SUNKclpYbElaWEpsSWdvZ0lDQWdJQ0FnSUgwc0NpQWdJQ0FnSUNBZ2V3b2dJQ0FnSUNBZ0lDQWdJbUZqZEdsdmJpSTZJQ0ppWVhObE5qUjFjbXdpQ2lBZ0lDQWdJQ0FnZlFvZ0lDQWdJQ0JkQ2lBZ0lDQjlMQW9nSUNBZ0luTmxjblpsY2lJNklIc0tJQ0FnSUNBZ0ltaGxZV1JsY25NaU9pQjdDaUFnSUNBZ0lDQWdJa3RsWlhBdFFXeHBkbVVpT2lBaWRISjFaU0lLSUNBZ0lDQWdmU3dLSUNBZ0lDQWdJblJ5WVc1elptOXliWE1pT2lCYkNpQWdJQ0FnSUNBZ2V3b2dJQ0FnSUNBZ0lDQWdJbUZqZEdsdmJpSTZJQ0ppWVhObE5qUjFjbXdpQ2lBZ0lDQWdJQ0FnZlN3S0lDQWdJQ0FnSUNCN0NpQWdJQ0FnSUNBZ0lDQWlZV04wYVc5dUlqb2dJbmh2Y2lJc0NpQWdJQ0FnSUNBZ0lDQWlkbUZzZFdVaU9pQWlhMlY1U0dWeVpTSUtJQ0FnSUNBZ0lDQjlDaUFnSUNBZ0lGMEtJQ0FnSUgwS0lDQjlDbjBLIn0=";
    //var profile_buf: [1024 * 4]u8 = undefined;
    //const profile_size = try decoder.calcSizeForSlice(b64_profile);
    //try decoder.decode(&profile_buf, b64_profile);
    //const profile_raw = profile_buf[0..profile_size];

    //const profile_parsed = try std.json.parseFromSlice(HttpxProfile, allocator, profile_raw, .{ .allocate = .alloc_always });
    //defer profile_parsed.deinit();
    //std.debug.print("{f}\n", .{profile_parsed.value});

    const b64_c2_config = "ewogICJuYW1lIjogIlRFU1QiLAogICJnZXQiOiB7CiAgICAidmVyYiI6ICJHRVQiLAogICAgInVyaXMiOiBbCiAgICAgICIvbXkvdXJpL3BhdGgiCiAgICBdLAogICAgImNsaWVudCI6IHsKICAgICAgImhlYWRlcnMiOiB7CiAgICAgICAgIlVzZXItQWdlbnQiOiAiTW96aWxsYS81LjAgKFdpbmRvd3MgTlQgMTAuMDsgV2luNjQ7IHg2NCkgQXBwbGVXZWJLaXQvNTM3LjM2IChLSFRNTCwgbGlrZSBHZWNrbykgQ2hyb21lLzEwNS4wLjAuMCBTYWZhcmkvNTM3LjM2IgogICAgICB9LAogICAgICAicGFyYW1ldGVycyI6IHsKICAgICAgICAiTXlLZXkiOiAidmFsdWUiCiAgICAgIH0sCiAgICAgICJkb21haW5fc3BlY2lmaWNfaGVhZGVycyI6IHsKICAgICAgICAiaHR0cHM6Ly9leGFtcGxlLmNvbTo0NDMiOiB7CiAgICAgICAgICAiVXNlci1BZ2VudCI6ICJUZXN0IgogICAgICAgIH0KICAgICAgfSwKICAgICAgIm1lc3NhZ2UiOiB7CiAgICAgICAgImxvY2F0aW9uIjogImNvb2tpZSIsCiAgICAgICAgIm5hbWUiOiAic2Vzc2lvbklEIgogICAgICB9LAogICAgICAidHJhbnNmb3JtcyI6IFsKICAgICAgICB7CiAgICAgICAgICAiYWN0aW9uIjogImJhc2U2NHVybCIKICAgICAgICB9CiAgICAgIF0KICAgIH0sCiAgICAic2VydmVyIjogewogICAgICAiaGVhZGVycyI6IHsKICAgICAgICAiU2VydmVyIjogIlNlcnZlciIsCiAgICAgICAgIkNhY2hlLUNvbnRyb2wiOiAibWF4LWFnZT0wLCBuby1jYWNoZSIKICAgICAgfSwKICAgICAgInRyYW5zZm9ybXMiOiBbCiAgICAgICAgewogICAgICAgICAgImFjdGlvbiI6ICJ4b3IiLAogICAgICAgICAgInZhbHVlIjogImtleUhlcmUiCiAgICAgICAgfSwKICAgICAgICB7CiAgICAgICAgICAiYWN0aW9uIjogImJhc2U2NHVybCIKICAgICAgICB9LAogICAgICAgIHsKICAgICAgICAgICJhY3Rpb24iOiAicHJlcGVuZCIsCiAgICAgICAgICAidmFsdWUiOiAie1wicmVzcG9uc2VcIjpcIiIKICAgICAgICB9LAogICAgICAgIHsKICAgICAgICAgICJhY3Rpb24iOiAiYXBwZW5kIiwKICAgICAgICAgICJ2YWx1ZSI6ICJcIn0iCiAgICAgICAgfSwKICAgICAgICB7CiAgICAgICAgICAiYWN0aW9uIjogIm5ldGJpb3MiCiAgICAgICAgfQogICAgICBdCiAgICB9CiAgfSwKICAicG9zdCI6IHsKICAgICJ1cmlzIjogWwogICAgICAiL215L290aGVyL3BhdGgiCiAgICBdLAogICAgInZlcmIiOiAiUE9TVCIsCiAgICAiY2xpZW50IjogewogICAgICAiaGVhZGVycyI6IHsKICAgICAgICAiVXNlci1BZ2VudCI6ICJNb3ppbGxhLzUuMCAoV2luZG93cyBOVCAxMC4wOyBXaW42NDsgeDY0KSBBcHBsZVdlYktpdC81MzcuMzYgKEtIVE1MLCBsaWtlIEdlY2tvKSBDaHJvbWUvMTA1LjAuMC4wIFNhZmFyaS81MzcuMzYiCiAgICAgIH0sCiAgICAgICJ0cmFuc2Zvcm1zIjogWwogICAgICAgIHsKICAgICAgICAgICJhY3Rpb24iOiAieG9yIiwKICAgICAgICAgICJ2YWx1ZSI6ICJrZXlIZXJlIgogICAgICAgIH0sCiAgICAgICAgewogICAgICAgICAgImFjdGlvbiI6ICJiYXNlNjR1cmwiCiAgICAgICAgfQogICAgICBdCiAgICB9LAogICAgInNlcnZlciI6IHsKICAgICAgImhlYWRlcnMiOiB7CiAgICAgICAgIktlZXAtQWxpdmUiOiAidHJ1ZSIKICAgICAgfSwKICAgICAgInRyYW5zZm9ybXMiOiBbCiAgICAgICAgewogICAgICAgICAgImFjdGlvbiI6ICJiYXNlNjR1cmwiCiAgICAgICAgfSwKICAgICAgICB7CiAgICAgICAgICAiYWN0aW9uIjogInhvciIsCiAgICAgICAgICAidmFsdWUiOiAia2V5SGVyZSIKICAgICAgICB9CiAgICAgIF0KICAgIH0KICB9Cn0K";
    var c2_config_buf: [1024 * 4]u8 = undefined;
    const c2_config_size = try decoder.calcSizeForSlice(b64_c2_config);
    try decoder.decode(&c2_config_buf, b64_c2_config);
    const c2_config_raw = c2_config_buf[0..c2_config_size];
    std.debug.print("{s}\n", .{c2_config_raw});
    const c2_config = try std.json.parseFromSlice(Httpx, allocator, c2_config_raw, .{ .allocate = .alloc_always });
    defer c2_config.deinit();
    std.debug.print("\n{f}\n", .{c2_config.value});

    //const response = try std.fs.cwd().readFileAlloc(allocator, "./checkin_response.bin", 51200);
    //defer allocator.free(response);
    //const decode = try applyTransforms(allocator, response, c2_config.value, .post, false, encoder, decoder);
    //defer allocator.free(decode);
    //std.debug.print("{s}\n", .{decode});

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
