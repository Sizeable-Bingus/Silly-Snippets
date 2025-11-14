const std = @import("std");

fn chunkFile(file_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});

    var reader_buf: [1024]u8 = undefined;
    var file_buf: [51200]u8 = undefined;
    var reader: std.fs.File.Reader = file.reader(&reader_buf);

    const file_size = try reader.getSize();
    const total_chunks = ((file_size + file_buf.len - 1) / file_buf.len);

    std.debug.print("[SIZE] {d}\n[CHUNKS] {d}\n", .{ file_size, total_chunks });

    while (true) {
        const bytes_read = try reader.interface.readSliceShort(&file_buf);
        //post file_buf[0..bytes_read];
        std.debug.print("{d}\n", .{bytes_read});
        if (bytes_read != file_buf.len) break;
    }
}

pub fn main() !void {
    try chunkFile("/Users/bingus/repos/JSON-Pass-Test/readTest.txt");
}
