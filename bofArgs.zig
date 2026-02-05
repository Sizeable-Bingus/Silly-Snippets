const std = @import("std");

pub fn main() !void {
    // Concatonate to buffer "z:a:s:0"
    const tasking =
        \\{"args":[["z",""],["s",0]],"file_id":"3867fa50-2570-4464-aeba-7f94d06ed77e"}
    ;

    var alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(alloc.deinit() == .ok);
    const dba = alloc.allocator();
    const parsed = try std.json.parseFromSlice(struct { file_id: []const u8, args: std.json.Value }, dba, tasking, .{});
    defer parsed.deinit();

    var buf: std.ArrayList([]const u8) = .empty;
    defer buf.deinit(dba);
    defer for (buf.items) |str| dba.free(str);
    const args = parsed.value.args;

    for (args.array.items) |typed_array| {
        const typed_pair = typed_array.array.items;
        const type_str = typed_pair[0].string;
        switch (typed_pair[1]) {
            .string => |str| try buf.append(dba, try std.fmt.allocPrint(dba, "{s}:{s}", .{ type_str, str })),
            .integer => |int| try buf.append(dba, try std.fmt.allocPrint(dba, "{s}:{d}", .{ type_str, int })),
            else => unreachable,
        }
    }

    for (buf.items) |typed_pair| {
        std.debug.print("[PAIR] {s}\n", .{typed_pair});
    }
}
