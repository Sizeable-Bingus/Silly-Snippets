const std = @import("std");

const uuid_len = 36;

const MythicUploadContext = struct {
    upload: struct {
        chunk_size: u32 = 512000,
        file_id: [uuid_len]u8,
        chunk_num: u32,
        full_path: ?[]u8 = null,
    },
    task_id: [uuid_len]u8,
    completed: bool,
    user_output: ?[]u8 = null,

    pub fn format(value: MythicUploadContext, writer: *std.Io.Writer) !void {
        const fmt_string =
            \\
            \\=====BEGIN_UPLOAD_CONTEXT=====
            \\upload: {{
            \\    chunk_size: {d}
            \\    file_id: {s}
            \\    chunk_num: {d}
            \\    full_path: {s}
            \\}}
            \\task_id: {s}
            \\completed: {}
            \\user_output: {s}
            \\=====END_UPLOAD_CONTEXT=====
            \\
        ;
        try writer.print(fmt_string, .{
            value.upload.chunk_size,
            value.upload.file_id,
            value.upload.chunk_num,
            value.upload.full_path orelse "(null)",
            value.task_id,
            value.completed,
            value.user_output orelse "(null)",
        });
    }
};

const AllUploadHandler = struct {
    var upload_list: std.ArrayList(MythicUploadContext) = .empty;

    fn deinit(allocator: std.mem.Allocator) void {
        upload_list.deinit(allocator);
    }

    fn addUpload(allocator: std.mem.Allocator, task_uuid: []const u8, file_uuid: []const u8) ![]const u8 {
        if (upload_list.items.len >= 5) return error.UploadListFull;

        var upload_context: MythicUploadContext = .{
            .upload = .{
                .file_id = undefined,
                .chunk_num = 1,
            },
            .task_id = undefined,
            .completed = false,
        };
        @memcpy(&upload_context.task_id, task_uuid);
        @memcpy(&upload_context.upload.file_id, file_uuid);

        try upload_list.append(allocator, upload_context);
        std.debug.print("{f}\n", .{upload_context});
        return std.json.Stringify.valueAlloc(allocator, upload_context, .{ .emit_null_optional_fields = false });
    }

    fn processUploads() !void {
        if (upload_list.items.len == 0) return;

        printUploads();
    }

    fn printUploads() void {
        for (upload_list.items) |context| {
            std.debug.print("{f}\n", .{context});
        }
    }
};

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_alloc.deinit() == .ok);
    const dba = debug_alloc.allocator();

    const out1 = try AllUploadHandler.addUpload(dba, "7f317a70-34a0-41c7-9021-d17990441730", "4bcbb5e8-956a-4a72-bfd2-b92d134c255a");
    defer dba.free(out1);

    const out2 = try AllUploadHandler.addUpload(dba, "e96d3c8f-f166-4da7-89fe-fdc90249d217", "ee923100-2b4f-4e2d-b3ff-5ae145b5714f");
    defer dba.free(out2);

    const out3 = try AllUploadHandler.addUpload(dba, "21b17d3b-410a-4ede-a50d-942f2cdb9628", "7d0bf4a5-ae88-4ad6-9471-e2d66100d10c");
    defer dba.free(out3);

    defer AllUploadHandler.deinit(dba);

    AllUploadHandler.printUploads();
}
