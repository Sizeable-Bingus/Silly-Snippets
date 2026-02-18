const std = @import("std");
const clr = @import("clr.zig");
const win = std.os.windows;

extern "kernel32" fn CreateNamedPipeA(
    lpName: win.LPCSTR,
    dwOpenMode: win.DWORD,
    dwPipeMode: win.DWORD,
    nMaxInstances: win.DWORD,
    nOutBufferSize: win.DWORD,
    nInBufferSize: win.DWORD,
    nDefaultTimeOut: win.DWORD,
    lpSecurityAttributes: ?*const win.SECURITY_ATTRIBUTES,
) callconv(.winapi) win.HANDLE;
extern "kernel32" fn CreateFileA(
    lpFileName: win.LPCSTR,
    dwDesiredAccess: win.DWORD,
    dwShareMode: win.DWORD,
    lpSecurityAttributes: ?*win.SECURITY_ATTRIBUTES,
    dwCreationDisposition: win.DWORD,
    dwFlagsAndAttributes: win.DWORD,
    hTemplateFile: ?win.HANDLE,
) callconv(.winapi) win.HANDLE;
extern "shell32" fn CommandLineToArgvW(lpCmdLine: win.LPWSTR, pNumArgs: *c_int) [*]win.LPWSTR;
extern "oleaut32" fn SafeArrayCreateVector(vt: clr.VARTYPE, lower_bound: win.LONG, count: win.ULONG) ?*clr.SAFEARRAY;
extern "oleaut32" fn SafeArrayPutElement(psa: *clr.SAFEARRAY, rgIndices: *win.LONG, pv: *anyopaque) win.HRESULT;
extern "oleaut32" fn SysAllocString(psz: ?[*]clr.OLECHAR) win.BSTR;
extern "oleaut32" fn SafeArrayCreate(vt: clr.VARTYPE, cDims: win.UINT, rgsabound: [*]clr.SAFEARRAYBOUND) callconv(.winapi) ?*clr.SAFEARRAY;
extern "oleaut32" fn SafeArrayAccessData(psa: *clr.SAFEARRAY, ppvData: **anyopaque) win.HRESULT;
extern "oleaut32" fn SafeArrayUnaccessData(psa: *clr.SAFEARRAY) win.HRESULT;
extern "oleaut32" fn SafeArrayDestroy(psa: *clr.SAFEARRAY) win.HRESULT;
extern "oleaut32" fn VariantClear(pvarg: *clr.VARIANTARG) win.HRESULT;

const fnCLRCreateInstance = *const fn (clsid: *const clr.GUID, riid: *const clr.GUID, ppInterface: *?*anyopaque) callconv(.winapi) win.HRESULT;
const fnAttachConsole = *const fn (dwProcessId: win.DWORD) callconv(.winapi) win.BOOL;
const fnAllocConsole = *const fn () callconv(.winapi) win.BOOL;
const fnGetConsoleWindow = *const fn () callconv(.winapi) win.HWND;
const fnShowWindow = *const fn (hWnd: win.HWND, nCmdShow: c_int) callconv(.winapi) win.BOOL;
const fnGetStdHandle = *const fn (nStdHandle: win.DWORD) callconv(.winapi) win.HANDLE;
const fnSetStdHandle = *const fn (nStdHandle: win.DWORD, hHandle: win.HANDLE) callconv(.winapi) win.BOOL;

const xCLSID_CorRuntimeHost: clr.GUID = .{
    .Data1 = 0xcb2f6723,
    .Data2 = 0xab3a,
    .Data3 = 0x11d2,
    .Data4 = .{ 0x9c, 0x40, 0x00, 0xc0, 0x4f, 0xa3, 0x0a, 0x3e },
};

const xIID_ICorRuntimeHost: clr.GUID = .{
    .Data1 = 0xcb2f6722,
    .Data2 = 0xab3a,
    .Data3 = 0x11d2,
    .Data4 = .{ 0x9c, 0x40, 0x00, 0xc0, 0x4f, 0xa3, 0x0a, 0x3e },
};

const xIID_AppDomain: clr.GUID = .{
    .Data1 = 0x05F696DC,
    .Data2 = 0x2B29,
    .Data3 = 0x3663,
    .Data4 = .{ 0xAD, 0x8B, 0xC4, 0x38, 0x9C, 0xF2, 0xA7, 0x13 },
};

const xCLSID_CLRMetaHost: clr.GUID = .{
    .Data1 = 0x9280188d,
    .Data2 = 0x0e8e,
    .Data3 = 0x4867,
    .Data4 = .{ 0xb3, 0x0c, 0x7f, 0xa8, 0x38, 0x84, 0xe8, 0xde },
};

const xIID_ICLRMetaHost: clr.GUID = .{
    .Data1 = 0xD332DB9E,
    .Data2 = 0xB9B3,
    .Data3 = 0x4125,
    .Data4 = .{ 0x82, 0x07, 0xA1, 0x48, 0x84, 0xF5, 0x32, 0x16 },
};

const xIID_ICLRRuntimeInfo: clr.GUID = .{
    .Data1 = 0xBD39D1D2,
    .Data2 = 0xBA2F,
    .Data3 = 0x486A,
    .Data4 = .{ 0x89, 0xB0, 0xB4, 0xB0, 0xCB, 0x46, 0x68, 0x91 },
};

fn utf8ToUtf16LeSentinel(allocator: std.mem.Allocator, utf8: []const u8) ![:0]const u16 {
    const utf16_buf = try allocator.alloc(u16, utf8.len + 1);
    const utf16_end = try std.unicode.utf8ToUtf16Le(utf16_buf, utf8);
    utf16_buf[utf16_end] = 0;
    return utf16_buf[0 .. utf16_buf.len - 1 :0];
}

const ReadFileError = error{FileToLarge} || std.fs.File.OpenError || std.fs.File.Reader.SizeError || std.Io.Reader.Error || std.mem.Allocator.Error;
fn readFile(allocator: std.mem.Allocator, file_path: []const u8) ReadFileError![]const u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});

    var reader_buf: [1024]u8 = undefined;
    var reader: std.fs.File.Reader = file.reader(&reader_buf);

    const file_size = try reader.getSize();
    if (file_size > 1024 * 1024) return error.FileToLarge;

    const file_buf = try allocator.alloc(u8, file_size);

    try reader.interface.readSliceAll(file_buf);

    return file_buf;
}

fn findVersion(assembly: []const u8) bool { // this doesnt work right
    const v4 = &.{ 0x76, 0x34, 0x2E, 0x30, 0x2E, 0x33, 0x30, 0x33, 0x31, 0x39 };

    for (assembly, 0..) |_, i| {
        if (std.mem.eql(u8, assembly[i .. i + v4.len], v4)) {
            return true;
        }
    }
    return false;
}

//fn createPipedConsole(_: std.mem.Allocator) !void {
//    const k32 = try std.DynLib.open("kernel32.dll");
//    defer k32.close();
//    const user32 = try std.DynLib.open("user32.dll");
//    defer user32.close();
//
//    const AttachConsole = k32.lookup(fnAttachConsole, "AttachConsole") orelse return error.SymbolNotFound;
//    const AllocConsole = k32.lookup(fnAllocConsole, "AllocConsole") orelse return error.SymbolNotFound;
//    const GetConsoleWindow = k32.lookup(fnAllocConsole, "GetConsoleWindow") orelse return error.SymbolNotFound;
//    const GetStdHandle = k32.lookup(fnGetStdHandle, "GetStdHandle") orelse return error.SymbolNotFound;
//    const SetStdHandle = k32.lookup(fnSetStdHandle, "SetStdHandle") orelse return error.SymbolNotFound;
//    const ShowWindow = user32.lookup(fnShowWindow, "ShowWindow") orelse return error.SymbolNotFound;
//
//    if (AttachConsole(@bitCast(@as(i32, -11))) != 0) {
//        if (AllocConsole() != 0) return error.FailedConsoleAllocation;
//        const h_window = GetConsoleWindow();
//        if (h_window == 0) return error.CouldNotGetConsole;
//        _ = ShowWindow(h_window, 0);
//    }
//
//    var h_pipe_read: win.HANDLE = undefined;
//    var h_pipe_write: win.HANDLE = undefined;
//    var sa = win.SECURITY_ATTRIBUTES{
//        .nLength = @sizeOf(win.SECURITY_ATTRIBUTES),
//        .bInheritHandle = win.TRUE,
//        .lpSecurityDescriptor = null,
//    };
//    _ = win.CreatePipe(&h_pipe_read, &h_pipe_write, &sa);
//
//    const stdout = GetStdHandle(-11);
//    if (stdout == win.INVALID_HANDLE_VALUE) return error.CouldNotGetStdout;
//
//    if (SetStdHandle(-11, h_pipe_read) == 0) return error.CouldNotSetStdout;
//}

fn startCLR(dotnet_version: win.LPCWSTR, ppClrMetaHost: **clr.ICLRMetaHost, ppClrRuntimeInfo: **clr.ICLRRuntimeInfo, ppICorRuntimeHost: **clr.ICorRuntimeHost) !bool {
    var dll = try std.DynLib.open("mscoree.dll");
    defer dll.close();

    const CLRCreateInstance = dll.lookup(fnCLRCreateInstance, "CLRCreateInstance") orelse return error.SymbolNotFound;

    var hr: win.HRESULT = CLRCreateInstance(&xCLSID_CLRMetaHost, &xIID_ICLRMetaHost, @ptrCast(ppClrMetaHost));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:CLRCreateInstance] : {}\n", .{hr});
    }

    const w_dotnet_version = std.mem.span(dotnet_version);
    var a_dotnet_version_buf: [1024]u8 = undefined;
    const a_dotnet_version_end = try std.unicode.utf16LeToUtf8(&a_dotnet_version_buf, w_dotnet_version);
    const a_dotnet_version = a_dotnet_version_buf[0..a_dotnet_version_end];

    std.debug.print("[startCLR:GetRuntime] {s} : {}\n", .{ a_dotnet_version, ppClrRuntimeInfo });
    hr = ppClrMetaHost.*.lpVtbl.*.GetRuntime(ppClrMetaHost.*, dotnet_version, &xIID_ICLRRuntimeInfo, @ptrCast(ppClrRuntimeInfo));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:GetRuntime] : {}\n", .{hr});
        return false;
    }

    var loadable: win.BOOL = win.FALSE;
    hr = ppClrRuntimeInfo.*.lpVtbl.*.IsLoadable(ppClrRuntimeInfo.*, &loadable);
    if (loadable != win.TRUE or hr != win.S_OK) {
        std.debug.print("[ERR:IsLoadable] : {} : {}\n", .{ loadable, hr });
        return false;
    }

    hr = ppClrRuntimeInfo.*.lpVtbl.*.GetInterface(ppClrRuntimeInfo.*, &xCLSID_CorRuntimeHost, &xIID_ICorRuntimeHost, @ptrCast(ppICorRuntimeHost));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:GetInterface] : {}\n", .{hr});
        return false;
    }

    hr = ppICorRuntimeHost.*.lpVtbl.*.Start(ppICorRuntimeHost.*);
    if (hr != win.S_OK) {
        std.debug.print("[ERR:Start] : {}\n", .{hr});
        return false;
    }

    std.debug.print("[startCLR] CLR Instance Created\n", .{});
    return true;
}

fn executeAssembly(allocator: std.mem.Allocator, assembly: []const u8, args: []const u8) !void {
    var dotnet_version: []const u8 = undefined;
    if (findVersion(assembly)) {
        std.debug.print("V4\n", .{});
        dotnet_version = "v4.0.30319";
    } else {
        std.debug.print("V2\n", .{});
        dotnet_version = "v2.0.50727";
    }
    const w_dotnet_version_buf = try allocator.alloc(u16, dotnet_version.len + 1);
    defer allocator.free(w_dotnet_version_buf);
    const w_dotnet_version_buf_end = try std.unicode.utf8ToUtf16Le(w_dotnet_version_buf, dotnet_version);
    w_dotnet_version_buf[w_dotnet_version_buf_end] = 0;
    const w_dotnet_version = w_dotnet_version_buf[0 .. w_dotnet_version_buf.len - 1 :0];

    var w_args_buf: []u16 = try allocator.alloc(u16, args.len + 1);
    defer allocator.free(w_args_buf);
    const w_args_end = try std.unicode.utf8ToUtf16Le(w_args_buf, args);
    w_args_buf[w_args_end] = 0;
    const w_args = w_args_buf[0 .. w_args_buf.len - 1 :0];

    var num_args: c_int = 0;
    const args_array = CommandLineToArgvW(w_args.ptr, &num_args);
    std.debug.print("num_args : {d}\n", .{num_args});

    var vt_psa: clr.VARIANT = std.mem.zeroes(clr.VARIANT);
    vt_psa.unnamed_0.unnamed_0.vt = (clr.VT_ARRAY | clr.VT_BSTR);
    vt_psa.unnamed_0.unnamed_0.unnamed_0.parray = SafeArrayCreateVector(clr.VT_BSTR, 0, @intCast(num_args));
    if (vt_psa.unnamed_0.unnamed_0.unnamed_0.parray == null) {
        std.debug.print("[ERR:SafeArrayCreateVector]\n", .{});
        return;
    }

    var i: win.LONG = 0;
    while (i < num_args) : (i += 1) {
        const a_str = SysAllocString(args_array[@intCast(i)]);
        if (SafeArrayPutElement(vt_psa.unnamed_0.unnamed_0.unnamed_0.parray, &i, a_str) != win.S_OK) {
            std.debug.print("[ERR:SafeArrayPutElement]\n", .{});
        }
    }

    var pCLRMetaHost: *clr.ICLRMetaHost = undefined;
    var pCLRRuntimeInfo: *clr.ICLRRuntimeInfo = undefined;
    var pCORRuntimeHost: *clr.ICorRuntimeHost = undefined;
    _ = try startCLR(w_dotnet_version, &pCLRMetaHost, &pCLRRuntimeInfo, &pCORRuntimeHost);

    var k32 = try std.DynLib.open("kernel32.dll");
    defer k32.close();
    var user32 = try std.DynLib.open("user32.dll");
    defer user32.close();
    const AttachConsole = k32.lookup(fnAttachConsole, "AttachConsole") orelse return error.SymbolNotFound;
    const AllocConsole = k32.lookup(fnAllocConsole, "AllocConsole") orelse return error.SymbolNotFound;
    const GetConsoleWindow = k32.lookup(fnAllocConsole, "GetConsoleWindow") orelse return error.SymbolNotFound;
    const GetStdHandle = k32.lookup(fnGetStdHandle, "GetStdHandle") orelse return error.SymbolNotFound;
    const SetStdHandle = k32.lookup(fnSetStdHandle, "SetStdHandle") orelse return error.SymbolNotFound;
    const ShowWindow = user32.lookup(fnShowWindow, "ShowWindow") orelse return error.SymbolNotFound;

    if (AttachConsole(@bitCast(@as(i32, -11))) != 0) {
        std.debug.print("Console does not exist\n", .{});
        if (AllocConsole() != 0) return error.FailedConsoleAllocation;
        const h_window = GetConsoleWindow();
        if (h_window == 0) return error.CouldNotGetConsole;
        _ = ShowWindow(@ptrFromInt(@as(usize, @intCast(h_window))), 0);
    }

    const h_pipe = CreateNamedPipeA("\\\\.\\pipe\\bingle", win.PIPE_ACCESS_DUPLEX, win.PIPE_TYPE_MESSAGE, 1, 65535, 65535, 0, null);
    if (h_pipe == win.INVALID_HANDLE_VALUE) return error.CannotCreatePipe;
    defer win.CloseHandle(h_pipe);

    //const pipe_path = try std.unicode.utf8ToUtf16LeAlloc(allocator, "\\\\.\\pipe\\bingle");
    //defer allocator.free(pipe_path);
    //const h_pipe_connection = try win.OpenFile(pipe_path, .{ .creation = win.OPEN_EXISTING, .access_mask = win.FILE_GENERIC_WRITE });
    //defer win.CloseHandle(h_pipe_connection);
    const h_pipe_connection = CreateFileA("\\\\.\\pipe\\bingle", win.GENERIC_WRITE, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    if (h_pipe_connection == win.INVALID_HANDLE_VALUE) return error.CannotOpenPipe;
    defer win.CloseHandle(h_pipe_connection);

    const stdout = GetStdHandle(win.STD_OUTPUT_HANDLE);
    if (stdout == win.INVALID_HANDLE_VALUE) return error.CouldNotGetStdout;

    std.debug.print("Setting stdout\n", .{});
    if (SetStdHandle(win.STD_OUTPUT_HANDLE, h_pipe_connection) == 0) return error.CouldNotSetStdout;
    std.debug.print("Set stdout\n", .{});
    //if (SetStdHandle(win.STD_OUTPUT_HANDLE, stdout) == 0) return error.CouldNotSetStdout;

    const w_appdomain = try utf8ToUtf16LeSentinel(allocator, "silly_domain");
    defer allocator.free(w_appdomain);
    var appdomain_thunk: *clr.IUnknown = undefined;
    var hr: win.HRESULT = pCORRuntimeHost.*.lpVtbl.*.CreateDomain(pCORRuntimeHost, w_appdomain, null, @ptrCast(&appdomain_thunk));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:CreateDomain] : {}\n", .{hr});
    }
    var appdomain: *clr.AppDomain = undefined;
    hr = appdomain_thunk.lpVtbl.*.QueryInterface(appdomain_thunk, &xIID_AppDomain, @ptrCast(&appdomain));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:QueryInterface] : {}\n", .{hr});
    }

    var rgsabound: [1]clr.SAFEARRAYBOUND = undefined;
    rgsabound[0].cElements = @intCast(assembly.len);
    rgsabound[0].lLbound = 0;
    var pv_data: *anyopaque = undefined;
    const safe_array = SafeArrayCreate(clr.VT_UI1, 1, &rgsabound).?;
    hr = SafeArrayAccessData(safe_array, &pv_data);
    if (hr != win.S_OK) {
        std.debug.print("[ERR:SafeArrayAccessData] : {}\n", .{hr});
    }

    @memcpy(@as([*]u8, @ptrCast(pv_data)), assembly);

    hr = SafeArrayUnaccessData(safe_array);
    if (hr != win.S_OK) {
        std.debug.print("[ERR:SafeArrayUnAccessData] : {}\n", .{hr});
    }

    var loaded_assembly: *clr.Assembly = undefined;
    hr = appdomain.lpVtbl.*.Load_3(appdomain, safe_array, @ptrCast(&loaded_assembly));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:Load_3] : {}\n", .{hr});
    }

    var method_info: *clr.MethodInfo = undefined;
    hr = loaded_assembly.lpVtbl.*.EntryPoint(loaded_assembly, @ptrCast(&method_info));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:EntryPoint] : {}\n", .{hr});
    }

    var ret_val = std.mem.zeroes(clr.VARIANT);
    var obj = std.mem.zeroes(clr.VARIANT);
    obj.unnamed_0.unnamed_0.vt = clr.VT_NULL;

    const psa_method_args = SafeArrayCreateVector(clr.VT_VARIANT, 0, 1).?;
    var idx: i32 = 0;
    _ = SafeArrayPutElement(psa_method_args, &idx, &vt_psa);

    std.debug.print("Invoking\n", .{});
    hr = method_info.lpVtbl.*.Invoke_3(method_info, obj, @ptrCast(psa_method_args), @ptrCast(&ret_val));

    //TODO: read output
    std.debug.print("Reading..\n", .{});
    var output_buf = try allocator.alloc(u8, 65535);
    defer allocator.free(output_buf);
    const output_size = try win.ReadFile(h_pipe, output_buf, null);
    const output = output_buf[0..output_size];

    _ = SetStdHandle(win.STD_OUTPUT_HANDLE, stdout);
    std.debug.print("[=================READ_PIPE=================]\n{s}\n[=================READ_PIPE=================]\n", .{output});

    _ = SafeArrayDestroy(safe_array);
    _ = VariantClear(&ret_val);
    _ = VariantClear(&obj);
    _ = VariantClear(&vt_psa);

    _ = SafeArrayDestroy(psa_method_args);
    _ = method_info.lpVtbl.*.Release(method_info);
    _ = loaded_assembly.lpVtbl.*.Release(loaded_assembly);
    _ = appdomain.lpVtbl.*.Release(appdomain);
    _ = appdomain_thunk.lpVtbl.*.Release(appdomain_thunk);
    _ = pCORRuntimeHost.lpVtbl.*.Release(pCORRuntimeHost);
    _ = pCLRRuntimeInfo.lpVtbl.*.Release(pCLRRuntimeInfo);
    _ = pCLRMetaHost.lpVtbl.*.Release(pCLRMetaHost);
}

pub fn main() !void {
    std.debug.print("[+] No assert vtable 19\n", .{});
    var debug_alloc = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_alloc.deinit() == .ok);
    const dba = debug_alloc.allocator();

    const args = try std.process.argsAlloc(dba);
    defer std.process.argsFree(dba, args);
    const dotnet_file_path = args[1];

    const dotnet = try readFile(dba, dotnet_file_path);
    defer dba.free(dotnet);

    try executeAssembly(dba, dotnet, "zyx");
}
