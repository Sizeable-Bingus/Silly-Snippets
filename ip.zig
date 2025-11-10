const std = @import("std");
const win = std.os.windows;

const ERROR_INSUFFICIENT_BUFFER = 122;

const MIB_IPADDRROW_W2K = extern struct {
    dwAddr: win.DWORD,
    dwIndex: win.DWORD,
    dwMask: win.DWORD,
    dwBCastAddr: win.DWORD,
    dwReasmSize: win.DWORD,
    unused1: win.USHORT,
    unused2: win.USHORT,
};

const MIB_IPADDRTABLE = extern struct {
    dwNumEntries: win.DWORD,
    //The ANY_SIZE trick doesnt work in zig so this is the best I got
    table: [10]MIB_IPADDRROW_W2K,
};

extern "iphlpapi" fn GetIpAddrTable(pIpAddrTable: *MIB_IPADDRTABLE, pdwSize: *win.ULONG, bOrder: win.BOOL) win.DWORD;

//Caller is responsible for freeing ip_slice
fn ipToString(allocator: std.mem.Allocator, ip: u32, ip_list: *std.ArrayList([]u8)) !void {
    const ipList = std.mem.asBytes(&ip);
    const ip_slice = try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ ipList[0], ipList[1], ipList[2], ipList[3] });
    errdefer allocator.free(ip_slice);
    try ip_list.append(allocator, ip_slice);
}

pub fn main() !void {
    const alloc = std.heap.smp_allocator;
    var dwSize: win.DWORD = 0;
    var ip_table_buf = try alloc.alloc(u8, @sizeOf(MIB_IPADDRTABLE));
    defer alloc.free(ip_table_buf);
    var ip_table = @as(*MIB_IPADDRTABLE, @ptrCast(@alignCast(ip_table_buf.ptr)));

    if (GetIpAddrTable(ip_table, &dwSize, 0) == ERROR_INSUFFICIENT_BUFFER) {
        ip_table_buf = try alloc.realloc(ip_table_buf, dwSize);
        ip_table = @as(*MIB_IPADDRTABLE, @ptrCast(@alignCast(ip_table_buf.ptr)));
    }

    const ret = GetIpAddrTable(ip_table, &dwSize, 0);
    if (ret != 0) {
        std.debug.print("[ERROR] {}\n", .{ret});
        return;
    }
    std.debug.print("Num entries: {}\n", .{ip_table.dwNumEntries});
    const upper = if (10 > ip_table.dwNumEntries) ip_table.dwNumEntries else 10;
    var list = try std.ArrayList([]u8).initCapacity(alloc, upper);
    errdefer list.deinit(alloc);
    for (0..upper) |i| {
        try ipToString(alloc, ip_table.table[i].dwAddr, &list);
    }
    for (0..list.items.len) |i| {
        std.debug.print("LIST: {s}\n", .{list.items[i]});
    }
}
