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

    const encoder = std.base64.Base64Encoder.init(std.base64.standard_alphabet_chars, '=');
    const decoder = std.base64.Base64Decoder.init(std.base64.standard_alphabet_chars, '=');

    const data = "U3VwZXIgc2lsbHkgZGF0YSBmb3Igc29tZSBzdXBlciBzaWxseXdhcmUK";
    var parsed = try parseProfileExampleJson(allocator, std.mem.span(std.os.argv[1]));
    defer parsed.deinit();

    std.debug.print("{f}\n\n", .{parsed.value});

    std.debug.print("[Original] {s}\n", .{data});
    //const transformed_data = try applyTransforms(allocator, data, parsed.value, .post, encoder);
    const transformed_data = try applyTransforms(allocator, data, parsed.value, .post, true, encoder, decoder);
    defer allocator.free(transformed_data);
    std.debug.print("[Transformed] {s}\n", .{transformed_data});

    const detransformed_data = try applyTransforms(allocator, transformed_data, parsed.value, .post, false, encoder, decoder);
    defer allocator.free(detransformed_data);
    std.debug.print("[Detransformed] {s}\n", .{detransformed_data});
}
