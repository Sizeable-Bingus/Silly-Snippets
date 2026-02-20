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
extern "kernel32" fn AttachConsole(dwProcessId: win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn AllocConsole() callconv(.winapi) win.BOOL;
extern "kernel32" fn GetConsoleWindow() callconv(.winapi) ?win.HWND;
extern "kernel32" fn GetStdHandle(nStdHandle: win.DWORD) callconv(.winapi) win.HANDLE;
extern "kernel32" fn SetStdHandle(nStdHandle: win.DWORD, hHandle: win.HANDLE) callconv(.winapi) win.BOOL;

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
const fnShowWindow = *const fn (hWnd: win.HWND, nCmdShow: c_int) callconv(.winapi) win.BOOL;

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

fn findVersion(assembly: []const u8) bool {
    const v4 = &.{ 0x76, 0x34, 0x2E, 0x30, 0x2E, 0x33, 0x30, 0x33, 0x31, 0x39 };

    for (assembly, 0..) |_, i| {
        if (std.mem.eql(u8, assembly[i .. i + v4.len], v4)) {
            return true;
        }
    }
    return false;
}

fn createPipedConsole(h_pipe: *win.HANDLE, h_pipe_connection: *win.HANDLE) !win.HANDLE {
    var user32 = try std.DynLib.open("user32.dll");
    defer user32.close();
    const ShowWindow = user32.lookup(fnShowWindow, "ShowWindow") orelse return error.SymbolNotFound;

    if (AttachConsole(@bitCast(@as(i32, -11))) != 0) {
        std.debug.print("Console does not exist\n", .{});
        if (AllocConsole() != 0) return error.FailedConsoleAllocation;
        const h_window = GetConsoleWindow();
        if (h_window == null) return error.CouldNotGetConsole;
        _ = ShowWindow(h_window.?, 0);
    }

    h_pipe.* = CreateNamedPipeA("\\\\.\\pipe\\bingle", win.PIPE_ACCESS_DUPLEX, win.PIPE_TYPE_MESSAGE, 1, 65535, 65535, 0, null);
    if (h_pipe.* == win.INVALID_HANDLE_VALUE) return error.CannotCreatePipe;

    h_pipe_connection.* = CreateFileA("\\\\.\\pipe\\bingle", win.GENERIC_WRITE, win.FILE_SHARE_READ, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    if (h_pipe_connection.* == win.INVALID_HANDLE_VALUE) return error.CannotOpenPipe;

    const stdout = GetStdHandle(win.STD_OUTPUT_HANDLE);
    if (stdout == win.INVALID_HANDLE_VALUE) return error.CannotGetStdout;

    if (SetStdHandle(win.STD_OUTPUT_HANDLE, h_pipe_connection.*) == 0) return error.CannottSetStdout;

    return stdout;
}

fn startCLR(dotnet_version: win.LPCWSTR, ppClrMetaHost: **clr.ICLRMetaHost, ppClrRuntimeInfo: **clr.ICLRRuntimeInfo, ppICorRuntimeHost: **clr.ICorRuntimeHost) !bool {
    var dll = try std.DynLib.open("mscoree.dll");
    defer dll.close();

    const CLRCreateInstance = dll.lookup(fnCLRCreateInstance, "CLRCreateInstance") orelse return error.SymbolNotFound;

    var hr: win.HRESULT = CLRCreateInstance(&clr.CLSID_CLRMetaHost, &clr.IID_ICLRMetaHost, @ptrCast(ppClrMetaHost));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:CLRCreateInstance] : {}\n", .{hr});
    }

    //const w_dotnet_version = std.mem.span(dotnet_version);
    //var a_dotnet_version_buf: [1024]u8 = undefined;
    //const a_dotnet_version_end = try std.unicode.utf16LeToUtf8(&a_dotnet_version_buf, w_dotnet_version);
    //const a_dotnet_version = a_dotnet_version_buf[0..a_dotnet_version_end];

    //std.debug.print("[startCLR:GetRuntime] {s} : {}\n", .{ a_dotnet_version, ppClrRuntimeInfo });
    hr = ppClrMetaHost.*.lpVtbl.*.GetRuntime(ppClrMetaHost.*, dotnet_version, &clr.IID_ICLRRuntimeInfo, @ptrCast(ppClrRuntimeInfo));
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

    hr = ppClrRuntimeInfo.*.lpVtbl.*.GetInterface(ppClrRuntimeInfo.*, &clr.CLSID_CorRuntimeHost, &clr.IID_ICorRuntimeHost, @ptrCast(ppICorRuntimeHost));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:GetInterface] : {}\n", .{hr});
        return false;
    }

    hr = ppICorRuntimeHost.*.lpVtbl.*.Start(ppICorRuntimeHost.*);
    if (hr != win.S_OK) {
        std.debug.print("[ERR:Start] : {}\n", .{hr});
        return false;
    }

    //std.debug.print("[startCLR] CLR Instance Created\n", .{});
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
    //std.debug.print("num_args : {d}\n", .{num_args});

    var vt_psa: clr.VARIANT = std.mem.zeroes(clr.VARIANT);
    defer _ = VariantClear(&vt_psa);
    vt_psa.v_union.v_payload.vt = (clr.VT_ARRAY | clr.VT_BSTR);
    vt_psa.v_union.v_payload.v_value.parray = SafeArrayCreateVector(clr.VT_BSTR, 0, @intCast(num_args));
    if (vt_psa.v_union.v_payload.v_value.parray == null) {
        std.debug.print("[ERR:SafeArrayCreateVector]\n", .{});
        return;
    }

    var i: win.LONG = 0;
    while (i < num_args) : (i += 1) {
        const a_str = SysAllocString(args_array[@intCast(i)]);
        if (SafeArrayPutElement(vt_psa.v_union.v_payload.v_value.parray, &i, a_str) != win.S_OK) {
            std.debug.print("[ERR:SafeArrayPutElement]\n", .{});
        }
    }

    var pCLRMetaHost: *clr.ICLRMetaHost = undefined;
    var pCLRRuntimeInfo: *clr.ICLRRuntimeInfo = undefined;
    var pCORRuntimeHost: *clr.ICorRuntimeHost = undefined;
    _ = try startCLR(w_dotnet_version, &pCLRMetaHost, &pCLRRuntimeInfo, &pCORRuntimeHost);
    defer _ = pCORRuntimeHost.lpVtbl.*.Release(pCORRuntimeHost);
    defer _ = pCLRRuntimeInfo.lpVtbl.*.Release(pCLRRuntimeInfo);
    defer _ = pCLRMetaHost.lpVtbl.*.Release(pCLRMetaHost);

    var h_pipe: win.HANDLE = undefined;
    var h_pipe_connection: win.HANDLE = undefined;
    const stdout = try createPipedConsole(&h_pipe, &h_pipe_connection);
    defer win.CloseHandle(h_pipe_connection);
    defer win.CloseHandle(h_pipe);

    const w_appdomain = try std.unicode.utf8ToUtf16LeAllocZ(allocator, "silly_domain");
    defer allocator.free(w_appdomain);
    var appdomain_thunk: *clr.IUnknown = undefined;
    var hr: win.HRESULT = pCORRuntimeHost.*.lpVtbl.*.CreateDomain(pCORRuntimeHost, w_appdomain, null, @ptrCast(&appdomain_thunk));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:CreateDomain] : {}\n", .{hr});
    }
    defer _ = appdomain_thunk.lpVtbl.*.Release(appdomain_thunk);

    var appdomain: *clr.AppDomain = undefined;
    hr = appdomain_thunk.lpVtbl.*.QueryInterface(appdomain_thunk, &clr.IID_AppDomain, @ptrCast(&appdomain));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:QueryInterface] : {}\n", .{hr});
    }
    defer _ = appdomain.lpVtbl.*.Release(appdomain);

    var rgsabound: [1]clr.SAFEARRAYBOUND = undefined;
    rgsabound[0].cElements = @intCast(assembly.len);
    rgsabound[0].lLbound = 0;
    var pv_data: *anyopaque = undefined;
    const safe_array = SafeArrayCreate(clr.VT_UI1, 1, &rgsabound).?;
    hr = SafeArrayAccessData(safe_array, &pv_data);
    if (hr != win.S_OK) {
        std.debug.print("[ERR:SafeArrayAccessData] : {}\n", .{hr});
    }
    defer _ = SafeArrayDestroy(safe_array);

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
    defer _ = loaded_assembly.lpVtbl.*.Release(loaded_assembly);

    var method_info: *clr.MethodInfo = undefined;
    hr = loaded_assembly.lpVtbl.*.EntryPoint(loaded_assembly, @ptrCast(&method_info));
    if (hr != win.S_OK) {
        std.debug.print("[ERR:EntryPoint] : {}\n", .{hr});
    }
    defer _ = method_info.lpVtbl.*.Release(method_info);

    const psa_method_args = SafeArrayCreateVector(clr.VT_VARIANT, 0, 1).?;
    defer _ = SafeArrayDestroy(psa_method_args);
    var idx: i32 = 0;
    _ = SafeArrayPutElement(psa_method_args, &idx, &vt_psa);

    var ret_val = std.mem.zeroes(clr.VARIANT);
    defer _ = VariantClear(&ret_val);

    var obj = std.mem.zeroes(clr.VARIANT);
    defer _ = VariantClear(&obj);
    obj.v_union.v_payload.vt = clr.VT_NULL;

    hr = method_info.lpVtbl.*.Invoke_3(method_info, obj, @ptrCast(psa_method_args), @ptrCast(&ret_val));

    var output_buf = try allocator.alloc(u8, 65535);
    defer allocator.free(output_buf);
    const output_size = try win.ReadFile(h_pipe, output_buf, null);
    const output = output_buf[0..output_size];

    _ = SetStdHandle(win.STD_OUTPUT_HANDLE, stdout);
    std.debug.print("[=================READ_PIPE=================]\n{s}\n[=================READ_PIPE=================]\n", .{output});
}

pub fn main() !void {
    std.debug.print("[+] No assert vtable 25\n", .{});
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
