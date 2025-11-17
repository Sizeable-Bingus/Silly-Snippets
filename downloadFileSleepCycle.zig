const std = @import("std");

const DownloadHandler = struct {
    // These args may need to be moved to main func because of init function stack
    var total_chunks: u64 = undefined;
    var chunk: u32 = undefined;
    var file_id: []const u8 = undefined;
    var task_id: []const u8 = undefined;
    var file: std.fs.File = undefined;
    var reader: std.fs.File.Reader = undefined;
    var reader_buf: [1024]u8 = undefined;
    var file_buf: [128]u8 = undefined;
    var b64_file_buf: [((file_buf.len * 4) / 3) + 2]u8 = undefined;

    fn initDownload(file_path: []const u8) !void {
        if (chunk != 0) return error.DownloadAlreadyInProgress;

        // Is this UB?
        file = try std.fs.cwd().openFile(file_path, .{});
        reader = file.reader(&reader_buf);

        const file_size = try reader.getSize();

        total_chunks = (file_size + file_buf.len - 1) / file_buf.len;
        chunk = 1;
        file_id = "test_file_id";
        task_id = "test_task_id";

        std.debug.print("[INIT] [SIZE] {d}\n[CHUNKS] {d}\n", .{ file_size, total_chunks });
    }

    fn getFileChunk(allocator: std.mem.Allocator, response_list: *std.ArrayList([]const u8)) !void {
        //if (chunk == 0) return error.DownloadNotInitialized;
        if (chunk == 0) return;

        const bytes_read = try reader.interface.readSliceShort(&file_buf);
        const encoder = std.base64.Base64Encoder.init(std.base64.standard_alphabet_chars, '=');
        const b64_file_chunk = encoder.encode(&b64_file_buf, file_buf[0..bytes_read]);
        try response_list.append(allocator, b64_file_chunk);

        if (bytes_read != file_buf.len) {
            total_chunks = 0;
            chunk = 0;
            file_id = "";
            task_id = "";
        } else {
            chunk += 1;
        }
    }
};

pub fn main() !void {
    const task_output_1 = .{
        .task_id = "abc-123",
        .output = "task 1 output",
        .special_field = "waba gaba",
        .explode = true,
    };
    const task_output_2 = .{
        .task_id = "098-zyx",
        .flag = 5959,
        .start = 0.64,
    };

    var debug_alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_alloc.deinit() == .ok);
    const allocator = debug_alloc.allocator();

    var response_array = try std.ArrayList([]const u8).initCapacity(allocator, 10);
    defer response_array.deinit(allocator);
    const json1 = try std.json.Stringify.valueAlloc(allocator, task_output_1, .{});
    const json2 = try std.json.Stringify.valueAlloc(allocator, task_output_2, .{});
    defer allocator.free(json1);
    defer allocator.free(json2);

    try response_array.append(allocator, json1);
    try response_array.append(allocator, json2);

    for (response_array.items) |response| {
        std.debug.print("[RESPONSE] {s}\n\n", .{response});
    }

    try DownloadHandler.initDownload("./cat.zig");

    //Sleep loop
    for (0..10) |_| {
        try response_array.append(allocator, json1);
        try DownloadHandler.getFileChunk(allocator, &response_array);
        //Send array
        for (response_array.items, 0..) |response, i| {
            std.debug.print("[RESPONSE {}] {s}\n\n", .{ i, response });
        }
        response_array.clearAndFree(allocator);
        std.Thread.sleep(2000 * 1_000_000);
    }
    //response_array.clearAndFree(allocator);
}
