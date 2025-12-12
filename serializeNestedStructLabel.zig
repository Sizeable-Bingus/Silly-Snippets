const std = @import("std");

const MythicUploadPost = struct {
    upload: struct {
        chunk_size: u32,
        file_id: []const u8,
        chunk_num: u32,
        full_path: []const u8,
    },
    task_id: []const u8,
};

pub fn main() !void {
    var alloc = std.heap.DebugAllocator(.{}){};
    const gpa = alloc.allocator();
    defer std.debug.assert(alloc.deinit() == .ok);

    const upload_post = MythicUploadPost{ .upload = .{ .chunk_size = 1, .file_id = "uuid", .chunk_num = 3, .full_path = "abc" }, .task_id = "1234-567" };
    const upload_json = try std.json.Stringify.valueAlloc(gpa, upload_post, .{});
    defer gpa.free(upload_json);

    std.debug.print("{s}\n", .{upload_json});
}
