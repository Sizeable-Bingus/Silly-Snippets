const std = @import("std");

const MythicTask = struct {
    command: []const u8,
    parameters: []const u8,
    timestamp: i64,
    id: []const u8,
};

const MythicTaskingResponse = struct {
    action: []const u8,
    tasks: []MythicTask,
};

pub fn main() !void {
    const alloc = std.heap.smp_allocator;
    const json_str =
        \\63f2a6aa-3c59-4581-ba57-7712a3a21c97{"tasks":[{"timestamp":1762969369,"command":"cat","parameters":"aba gaba","id":"9e2fd87c-31a6-4ecf-ad3f-661cfb7293b9"}],"action":"get_tasking"}
    ;

    std.debug.print("[INPUT] {s}\n", .{json_str[36..]});
    const tasking_response = try std.json.parseFromSlice(MythicTaskingResponse, alloc, json_str[36..], .{});
    defer tasking_response.deinit();
    std.debug.print("[TASKING RESPONSE] {}\n", .{tasking_response.value});
}
