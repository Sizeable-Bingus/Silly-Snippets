const std = @import("std");

pub fn main() !void {
    const response1 =
        \\"{"task_id":"one-894a-40b4-8bf8-5e5f0244d61e","user_output":"C:\\Users\\bingus","completed":true}
    ;
    const response2 =
        \\"{"task_id":"two-894a-40b4-8bf8-5e5f0244d61e","user_output":"C:\\Users\\bingus","completed":true}
    ;
    const response3 =
        \\"{"task_id":"three-894a-40b4-8bf8-5e5f0244d61e","user_output":"C:\\Users\\bingus","completed":true}
    ;

    const post =
        \\ef1df4f4-ed01-401c-a62b-6a6d2f637ac2{"action":"post_response","responses":[]}
    ;

    const alloc = std.heap.smp_allocator;
    const responses = [_][]const u8{ response1, response2, response3 };
    const new_responses = try alloc.alloc([]const u8, responses.len);

    for (responses, 0..) |response, i| {
        new_responses[i] = if (i + 1 != responses.len) try std.fmt.allocPrint(alloc, "{s}{s}", .{ response, ", " }) else try std.fmt.allocPrint(alloc, "{s}", .{response});
    }

    const needle = "\"responses\":[";
    const responses_string = try std.mem.concat(alloc, u8, new_responses);
    const index = std.mem.indexOf(u8, post, needle).? + needle.len;
    const post_json = try std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ post[0..index], responses_string, post[index..] });

    std.debug.print("{s}\n", .{post_json});
}
