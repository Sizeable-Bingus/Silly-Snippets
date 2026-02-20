const std = @import("std");
const win = std.os.windows;

pub const CLSID_CorRuntimeHost: GUID = .{
    .Data1 = 0xcb2f6723,
    .Data2 = 0xab3a,
    .Data3 = 0x11d2,
    .Data4 = .{ 0x9c, 0x40, 0x00, 0xc0, 0x4f, 0xa3, 0x0a, 0x3e },
};

pub const IID_ICorRuntimeHost: GUID = .{
    .Data1 = 0xcb2f6722,
    .Data2 = 0xab3a,
    .Data3 = 0x11d2,
    .Data4 = .{ 0x9c, 0x40, 0x00, 0xc0, 0x4f, 0xa3, 0x0a, 0x3e },
};

pub const IID_AppDomain: GUID = .{
    .Data1 = 0x05F696DC,
    .Data2 = 0x2B29,
    .Data3 = 0x3663,
    .Data4 = .{ 0xAD, 0x8B, 0xC4, 0x38, 0x9C, 0xF2, 0xA7, 0x13 },
};

pub const CLSID_CLRMetaHost: GUID = .{
    .Data1 = 0x9280188d,
    .Data2 = 0x0e8e,
    .Data3 = 0x4867,
    .Data4 = .{ 0xb3, 0x0c, 0x7f, 0xa8, 0x38, 0x84, 0xe8, 0xde },
};

pub const IID_ICLRMetaHost: GUID = .{
    .Data1 = 0xD332DB9E,
    .Data2 = 0xB9B3,
    .Data3 = 0x4125,
    .Data4 = .{ 0x82, 0x07, 0xA1, 0x48, 0x84, 0xF5, 0x32, 0x16 },
};

pub const IID_ICLRRuntimeInfo: GUID = .{
    .Data1 = 0xBD39D1D2,
    .Data2 = 0xBA2F,
    .Data3 = 0x486A,
    .Data4 = .{ 0x89, 0xB0, 0xB4, 0xB0, 0xCB, 0x46, 0x68, 0x91 },
};

pub const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

pub const OLECHAR = u16;
pub const VARTYPE = u16;

pub const SAFEARRAY = extern struct {
    _reserved: u8,
};

pub const SAFEARRAYBOUND = extern struct {
    cElements: win.ULONG,
    lLbound: win.LONG,
};

const variant_value = extern union {
    parray: [*c]SAFEARRAY,
};

const variant_payload = extern struct {
    vt: VARTYPE,
    wReserved1: u16,
    wReserved2: u16,
    wReserved3: u16,
    v_value: variant_value,
};

const variant_union = extern union {
    v_payload: variant_payload,
};

pub const VARIANT = extern struct {
    v_union: variant_union,
};

pub const VARIANTARG = VARIANT;

pub const VT_NULL: VARTYPE = 1;
pub const VT_BSTR: VARTYPE = 8;
pub const VT_VARIANT: VARTYPE = 12;
pub const VT_UI1: VARTYPE = 17;
pub const VT_ARRAY: VARTYPE = 0x2000;

pub const IUnknown = extern struct {
    lpVtbl: [*c]IUnknownVtbl,
};

pub const IUnknownVtbl = extern struct {
    QueryInterface: *const fn ([*c]IUnknown, [*c]const GUID, [*c]?*anyopaque) callconv(.c) win.HRESULT,
    AddRef: *const fn ([*c]IUnknown) callconv(.c) win.ULONG,
    Release: *const fn ([*c]IUnknown) callconv(.c) win.ULONG,
};

pub const ICLRMetaHost = extern struct {
    lpVtbl: [*c]ICLRMetaHostVtbl,
};

pub const ICLRMetaHostVtbl = extern struct {
    QueryInterface: *const fn ([*c]ICLRMetaHost, [*c]const GUID, [*c]?*anyopaque) callconv(.c) win.HRESULT,
    AddRef: *const fn ([*c]ICLRMetaHost) callconv(.c) win.ULONG,
    Release: *const fn ([*c]ICLRMetaHost) callconv(.c) win.ULONG,
    GetRuntime: *const fn ([*c]ICLRMetaHost, win.LPCWSTR, [*c]const GUID, [*c]win.LPVOID) callconv(.c) win.HRESULT,
};

pub const ICLRRuntimeInfo = extern struct {
    lpVtbl: [*c]ICLRRuntimeInfoVtbl,
};

pub const ICLRRuntimeInfoVtbl = extern struct {
    QueryInterface: *const fn ([*c]ICLRRuntimeInfo, [*c]const GUID, [*c]?*anyopaque) callconv(.c) win.HRESULT,
    AddRef: *const fn ([*c]ICLRRuntimeInfo) callconv(.c) win.ULONG,
    Release: *const fn ([*c]ICLRRuntimeInfo) callconv(.c) win.ULONG,
    _reserved3_to_8: [6]*const anyopaque,
    GetInterface: *const fn ([*c]ICLRRuntimeInfo, [*c]const GUID, [*c]const GUID, [*c]win.LPVOID) callconv(.c) win.HRESULT,
    IsLoadable: *const fn ([*c]ICLRRuntimeInfo, [*c]win.BOOL) callconv(.c) win.HRESULT,
};

pub const ICorRuntimeHost = extern struct {
    lpVtbl: [*c]ICorRuntimeHostVtbl,
};

pub const ICorRuntimeHostVtbl = extern struct {
    QueryInterface: *const fn ([*c]ICorRuntimeHost, [*c]const GUID, [*c]?*anyopaque) callconv(.c) win.HRESULT,
    AddRef: *const fn ([*c]ICorRuntimeHost) callconv(.c) win.ULONG,
    Release: *const fn ([*c]ICorRuntimeHost) callconv(.c) win.ULONG,
    _reserved3_to_9: [7]*const anyopaque,
    Start: *const fn ([*c]ICorRuntimeHost) callconv(.c) win.HRESULT,
    _reserved11: *const anyopaque,
    CreateDomain: *const fn ([*c]ICorRuntimeHost, win.LPCWSTR, [*c]IUnknown, [*c][*c]IUnknown) callconv(.c) win.HRESULT,
};

pub const AppDomain = extern struct {
    lpVtbl: [*c]AppDomainVtbl,
};

pub const AppDomainVtbl = extern struct {
    QueryInterface: *const fn ([*c]AppDomain, [*c]const GUID, [*c]?*anyopaque) callconv(.c) win.HRESULT,
    AddRef: *const fn ([*c]AppDomain) callconv(.c) win.ULONG,
    Release: *const fn ([*c]AppDomain) callconv(.c) win.ULONG,
    _reserved3_to_44: [42]*const anyopaque,
    Load_3: *const fn ([*c]AppDomain, [*c]SAFEARRAY, [*c][*c]Assembly) callconv(.c) win.HRESULT,
};

pub const Assembly = extern struct {
    lpVtbl: [*c]AssemblyVtbl,
};

pub const AssemblyVtbl = extern struct {
    QueryInterface: *const fn ([*c]Assembly, [*c]const GUID, [*c]?*anyopaque) callconv(.c) win.HRESULT,
    AddRef: *const fn ([*c]Assembly) callconv(.c) win.ULONG,
    Release: *const fn ([*c]Assembly) callconv(.c) win.ULONG,
    _reserved3_to_15: [13]*const anyopaque,
    EntryPoint: *const fn ([*c]Assembly, [*c][*c]MethodInfo) callconv(.c) win.HRESULT,
};

pub const MethodInfo = extern struct {
    lpVtbl: [*c]MethodInfoVtbl,
};

pub const MethodInfoVtbl = extern struct {
    QueryInterface: *const fn ([*c]MethodInfo, [*c]const GUID, [*c]?*anyopaque) callconv(.c) win.HRESULT,
    AddRef: *const fn ([*c]MethodInfo) callconv(.c) win.ULONG,
    Release: *const fn ([*c]MethodInfo) callconv(.c) win.ULONG,
    _reserved3_to_36: [34]*const anyopaque,
    Invoke_3: *const fn ([*c]MethodInfo, VARIANT, [*c]SAFEARRAY, [*c]VARIANT) callconv(.c) win.HRESULT,
};
