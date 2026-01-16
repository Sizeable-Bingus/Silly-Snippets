const std = @import("std");

const FileContext = struct {
    file: std.fs.File,
    writer_buf: [1024]u8 = undefined,
    writer: std.fs.File.Writer,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !*FileContext {
        const ctx = try allocator.create(FileContext);
        errdefer allocator.destroy(ctx);

        ctx.file = try std.fs.cwd().createFile(path, .{});
        ctx.writer = ctx.file.writer(&ctx.writer_buf);
        return ctx;
    }

    pub fn write(self: *FileContext, bytes: []const u8) !void {
        try self.writer.interface.writeAll(bytes);
        try self.writer.interface.flush();
    }

    pub fn deinit(self: *FileContext, allocator: std.mem.Allocator) void {
        self.file.close();
        allocator.destroy(self);
    }
};

fn scopeTest(allocator: std.mem.Allocator, path: []const u8) !*FileContext {
    return FileContext.init(allocator, path);
}

const MiniHandler = struct {
    var file_context: *FileContext = undefined;
    fn inFileTasking(allocator: std.mem.Allocator, path: []const u8) !void {
        file_context = try FileContext.init(allocator, path);
    }

    fn downBytes(bytes: []const u8) !void {
        try file_context.write(bytes);
    }
};

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_alloc.deinit() == .ok);
    const dba = debug_alloc.allocator();

    try MiniHandler.inFileTasking(dba, "/tmp/b.txt");
    try MiniHandler.downBytes("abcdefg\n");
}
