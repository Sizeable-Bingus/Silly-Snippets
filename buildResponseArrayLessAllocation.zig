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

    var debug_alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_alloc.deinit() == .ok);
    const alloc = debug_alloc.allocator();

    const responses = [_][]const u8{ response1, response2, response3 };

    // A ',' character for each response except the last one
    var total_size: usize = responses.len - 1;
    for (responses) |response| {
        total_size += response.len;
    }
    std.debug.print("{}\n", .{total_size});

    const serialized_responses_buf = try alloc.alloc(u8, total_size);
    defer alloc.free(serialized_responses_buf);
    var serialzied_responses_writer = std.Io.Writer.fixed(serialized_responses_buf);
    for (responses, 1..) |resp, i| {
        _ = try serialzied_responses_writer.writeAll(resp);
        if (i != responses.len)
            _ = try serialzied_responses_writer.writeAll(",");
    }
    //Writer.fixed hash noopFlush
    //try serialzied_responses_writer.flush();
    std.debug.print("{s}\n\n", .{serialized_responses_buf});

    const needle = "\"responses\":[";
    const index = std.mem.indexOf(u8, post, needle).? + needle.len;
    const post_json = try std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ post[0..index], serialized_responses_buf, post[index..] });
    defer alloc.free(post_json);

    std.debug.print("{s}\n", .{post_json});
}
