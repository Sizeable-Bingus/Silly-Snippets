const std = @import("std");

fn writeFile(file_path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    var writer_buf: [1024]u8 = undefined;
    var writer = file.writer(&writer_buf);
    try writer.interface.writeAll(data);
    try writer.interface.flush();
}

pub fn main() !void {
    try writeFile("writeTest.txt", "silly goofy file contents\n");
}
