const std = @import("std");

const MythicTask = struct {
    command: []const u8,
    parameters: []const u8,
    timestamp: f64,
    id: []const u8,
};

fn findTasksArray(server_response: []const u8) []const u8 {
    const needle = "\"tasks\":";
    const tasks_begin = std.mem.indexOf(u8, server_response, needle).? + needle.len;
    const tasks_end = std.mem.indexOf(u8, server_response[tasks_begin..], "]").? + tasks_begin + 1;
    return server_response[tasks_begin..tasks_end];
}

pub fn main() !void {
    const server_response =
        \\{"action":"get_tasking","tasks":[{"command": "command name","parameters":"command param string","timestamp":1578706611.324671,"id":"task uuid"}], "responses":[{"task_id":"response_1"}]}
    ;
    const server_response_2 =
        \\{"action":"get_tasking","tasks":[], "responses":[{"task_id":"response_1"}]}
    ;

    var debug_alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_alloc.deinit() == .ok);
    const allocator = debug_alloc.allocator();

    const parsed = findTasksArray(server_response);
    std.debug.print("{s}\n", .{parsed});
    const parsed2 = findTasksArray(server_response_2);
    std.debug.print("{s}\n", .{parsed2});

    const bigparse = try std.json.parseFromSlice([]MythicTask, allocator, parsed, .{});
    defer bigparse.deinit();
    std.debug.print("{d} : {s}\n", .{ bigparse.value.len, bigparse.value[0].command });

    const bigparse2 = try std.json.parseFromSlice([]MythicTask, allocator, parsed2, .{});
    defer bigparse2.deinit();
    if (bigparse2.value.len != 0) {
        std.debug.print("{d} : {s}\n", .{ bigparse2.value.len, bigparse2.value[0].command });
    } else std.debug.print("{d} : no tasking\n", .{bigparse2.value.len});
}
