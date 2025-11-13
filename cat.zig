const std = @import("std");

fn cat(allocator: std.mem.Allocator, _: []const u8, file_path: []const u8) ![]const u8 {
    const is_full_path = std.mem.containsAtLeast(u8, file_path, 1, "C:\\");
    const is_fulle_path_unc = std.mem.containsAtLeast(u8, file_path, 1, "\\\\");
    std.debug.print("[FULLPATH] {} : {}\n", .{ is_full_path, is_fulle_path_unc });
    if (is_full_path or is_fulle_path_unc or true) {
        const file = try std.fs.openFileAbsolute(file_path, .{});
        const file_size = try file.getEndPos();
        const file_buf = try allocator.alloc(u8, file_size);
        var buf: [1024]u8 = undefined;
        var reader: std.fs.File.Reader = file.reader(&buf);
        try reader.interface.readSliceAll(file_buf);
        return file_buf;
    }
}

pub fn main() !void {
    const content = try cat(std.heap.smp_allocator, "", "/tmp/a.txt");
    std.debug.print("{s}\n", .{content});
}
