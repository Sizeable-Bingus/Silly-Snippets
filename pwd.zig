const std = @import("std");

fn pwd(_: []const u8, cwd_buf: []u8) ![]u8 {
    const cwd_handle = std.fs.cwd();
    const cwd = try cwd_handle.realpath(".", cwd_buf);
    return cwd;
}

pub fn main() !void {
    var cwd_buf: [1024]u8 = undefined;
    const cwd = try pwd("ABCD", &cwd_buf);

    std.debug.print("[PWD] {s}\n", .{cwd});
}
