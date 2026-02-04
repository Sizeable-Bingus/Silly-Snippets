const std = @import("std");

pub fn main() !void {
    // Concatonate to buffer "z:a:s:0"
    const tasking =
        \\{"args":[["z","cstring"],["s",0]],"file_id":"3867fa50-2570-4464-aeba-7f94d06ed77e"}
    ;

    var alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(alloc.deinit() == .ok);
    const dba = alloc.allocator();
    const parsed = try std.json.parseFromSlice(struct { file_id: []const u8, args: std.json.Value }, dba, tasking, .{});
    defer parsed.deinit();

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(dba);
    const args = parsed.value.args;

    for (args.array.items) |typed_array| {
        const typed_pair = typed_array.array.items;
        const type_str = typed_pair[0].string;
        try buf.appendSlice(dba, type_str);
        try buf.append(dba, ':');
        switch (typed_pair[1]) {
            .string => |str| try buf.appendSlice(dba, str),
            .integer => |int| try buf.writer(dba).print("{d}", .{int}),
            else => continue,
        }
        try buf.append(dba, ':');
    }

    std.debug.print("{s}\n", .{buf.items[0 .. buf.items.len - 1]});
}
