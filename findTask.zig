const std = @import("std");

const Task = struct {
    task_id: []const u8,
    boolean: bool,
    number: u32,
};

const OtherTask = struct {
    task_id: []const u8,
    user_output: []const u8,
    float: f32,
};

//fn findTask(T: type, task_id: []const u8, server_response: []const u8) !std.json.Parsed(T) {
fn findTask(allocator: std.mem.Allocator, T: type, task_id: []const u8, server_response: []const u8) !std.json.Parsed(T) {
    //Find download task response
    const task_index = std.mem.indexOf(u8, server_response, task_id);
    if (task_index == null) return error.TaskNotFound;

    const index = task_index.? - "{\"task_id\":\"".len;
    const end_index = std.mem.indexOf(u8, server_response[index..], "}").? + index + 1;

    std.debug.print("{s}\n", .{server_response[index..end_index]});
    return try std.json.parseFromSlice(T, allocator, server_response[index..end_index], .{ .allocate = .alloc_always });
}

pub fn main() !void {
    const response1 =
        \\{"task_id":"one-894a-40b4-8bf8-5e5f0244d61e","user_output":"C:\\Users\\bingus","completed":true}
    ;
    const response2 =
        \\{"task_id":"two-894a-40b4-8bf8-5e5f0244d61e","boolean":false ,"number":499}
    ;
    const response3 =
        \\{"task_id":"three-894a-40b4-8bf8-5e5f0244d61e","user_output":"C:\\Users\\bingus","float":0.32}
    ;
    const server_response = "[" ++ response1 ++ "," ++ response2 ++ "," ++ response3 ++ "]";

    var dba = std.heap.DebugAllocator(.{}){};
    const allocator = dba.allocator();
    defer std.debug.assert(dba.deinit() == .ok);

    std.debug.print("{s}\n\n", .{server_response});
    const serialized_1 = try findTask(allocator, Task, "two-894a-40b4-8bf8-5e5f0244d61e", server_response);
    defer serialized_1.deinit();
    const serialized_2 = try findTask(allocator, OtherTask, "three-894a-40b4-8bf8-5e5f0244d61e", server_response);
    defer serialized_2.deinit();

    std.debug.print("{}\n", .{serialized_1.value});
    std.debug.print("{}\n", .{serialized_2.value});
}
