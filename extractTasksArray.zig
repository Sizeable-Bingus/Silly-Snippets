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
    var x: usize = 0;
    const tasks_end = for (server_response[tasks_begin + 1 ..], 0..) |c, i| {
        switch (c) {
            '[' => {
                //std.debug.print("Found opening brace\n", .{});
                x += 1;
            },
            ']' => {
                if (x == 0) break i + tasks_begin + 2 else x -= 1;
            },
            else => continue,
        }
    } else unreachable;
    std.debug.print("{d} : {d}\n", .{ tasks_begin, tasks_end });
    return server_response[tasks_begin..tasks_end];
}

pub fn main() !void {
    const server_response =
        \\{"action":"get_tasking","tasks":[{"command": "command name","parameters":"command param string","timestamp":1578706611.324671,"id":"task uuid"}], "responses":[{"task_id":"response_1"}]}
    ;
    const server_response_2 =
        \\{"action":"get_tasking","tasks":[], "responses":[{"task_id":"response_1"}]}
    ;
    const server_response_3 =
        \\{"action":"get_tasking","tasks":[{"command": "command name","parameters":"["a","b","c"]","timestamp":1578706611.324671,"id":"task uuid"}], "responses":[{"task_id":"response_1"}]}
    ;

    const server_response_4 =
        \\{"tasks":[],"action":"get_tasking","responses":[{"task_id":"daaa9de5-6bcc-47d3-9ee3-30dab0612a18","status":"success","file_id":"fd85e316-3553-45b1-bd12-da31ba4cd32f"}]}
    ;

    var debug_alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_alloc.deinit() == .ok);
    const allocator = debug_alloc.allocator();

    const parsed = findTasksArray(server_response);
    std.debug.print("{s}\n", .{parsed});
    const parsed2 = findTasksArray(server_response_2);
    std.debug.print("{s}\n", .{parsed2});
    const parsed3 = findTasksArray(server_response_3);
    std.debug.print("{s}\n", .{parsed3});
    const parsed4 = findTasksArray(server_response_4);
    std.debug.print("{s}\n", .{parsed4});

    const bigparse = try std.json.parseFromSlice([]MythicTask, allocator, parsed, .{});
    defer bigparse.deinit();
    std.debug.print("{d} : {s}\n", .{ bigparse.value.len, bigparse.value[0].command });

    const bigparse2 = try std.json.parseFromSlice([]MythicTask, allocator, parsed2, .{});
    defer bigparse2.deinit();
    if (bigparse2.value.len != 0) {
        std.debug.print("{d} : {s}\n", .{ bigparse2.value.len, bigparse2.value[0].command });
    } else std.debug.print("{d} : no tasking\n", .{bigparse2.value.len});
}
