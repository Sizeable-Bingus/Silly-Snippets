const std = @import("std");

fn ls(allocator: std.mem.Allocator, _: []const u8, directory: []const u8) ![]const u8 {
    var dir: std.fs.Dir.Iterator = undefined;
    if (directory.len != 0) {
        if (std.fs.path.isAbsolute(directory)) {
            dir = (try std.fs.openDirAbsolute(directory, .{ .iterate = true })).iterate();
        } else {
            const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
            const absolute_path = try std.fs.path.resolve(allocator, &.{ cwd, directory });
            defer allocator.free(cwd);
            defer allocator.free(absolute_path);
            dir = (try std.fs.openDirAbsolute(absolute_path, .{ .iterate = true })).iterate();
        }
    } else {
        dir = (try std.fs.cwd().openDir(".", .{ .iterate = true })).iterate();
    }

    var allocating_writer = std.Io.Writer.Allocating.init(allocator);
    defer allocating_writer.deinit();
    while (try dir.next()) |entry| {
        std.debug.print("{s}\n", .{entry.name});
        try allocating_writer.writer.writeAll(entry.name);
        try allocating_writer.writer.writeAll("\n");
    }

    return try allocating_writer.toOwnedSlice();
}

pub fn main() !void {
    const content = try ls(std.heap.smp_allocator, "", "");
    defer std.heap.smp_allocator.free(content);
    std.debug.print("{s}", .{content});
}
