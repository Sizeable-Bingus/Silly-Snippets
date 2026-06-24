#include <windows.h>
#include <psapi.h>
#include <stdio.h>

#define H_SENTINEL (HANDLE)-1

enum IPC_OP {
    SEND_HANDLE,
    CALL
};

typedef struct _IPC_HANDLE {
    enum IPC_OP op;
    HANDLE handle;
} IPC_HANDLE;

typedef struct _IPC_CALL {
    enum IPC_OP op;
    LPVOID func;
    DWORD argc;
    UINT_PTR args[10];
} IPC_CALL;

typedef struct _IPC_VP_RET {
    BOOL vp_ret;
    DWORD old_protect;
} IPC_VP_RET;

VOID sendMessage(HANDLE h_write, HANDLE h_read, PBYTE send, SIZE_T send_len, PBYTE recv, SIZE_T recv_len) {
    DWORD written = 0;
    if (!WriteFile(h_write, send, send_len, &written, NULL)) {
        ExitProcess(1);
    }

    if (recv != NULL) {
        DWORD read = 0;
        ReadFile(h_read, recv, recv_len, &read, NULL);
    }
}

void startChild(PHANDLE ph_write, PHANDLE ph_read) {
    CHAR proc_name[MAX_PATH];
    DWORD proc_size = sizeof(proc_name);
    QueryFullProcessImageNameA(GetCurrentProcess(), 0, proc_name, &proc_size);
    
    HANDLE h_job = CreateJobObjectA(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = { 0 };
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(h_job, JobObjectExtendedLimitInformation, &info, sizeof(info));

    HANDLE parent_write, child_write;
    HANDLE parent_read, child_read;
    SECURITY_ATTRIBUTES sa = { .nLength = sizeof(sa), .lpSecurityDescriptor = NULL, .bInheritHandle = TRUE };
    CreatePipe(&parent_read, &parent_write, &sa, 0);
    SetHandleInformation(parent_write, HANDLE_FLAG_INHERIT, 0);
    CreatePipe(&child_read, &child_write, &sa, 0);
    SetHandleInformation(child_read, HANDLE_FLAG_INHERIT, 0);
           
    PROCESS_INFORMATION pi;
    STARTUPINFO si = { .cb = sizeof(si) };
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = parent_read;
    si.hStdOutput = child_write;
    si.hStdError = H_SENTINEL;
    CreateProcessA(proc_name, NULL, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
    AssignProcessToJobObject(h_job, pi.hProcess);

    *ph_write = parent_write;
    *ph_read = child_read;

    HANDLE h_parent = 0;
    DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(), pi.hProcess, &h_parent, PROCESS_VM_OPERATION, FALSE, 0);

    IPC_HANDLE ipc_handle = { .op = SEND_HANDLE, .handle = h_parent };
    sendMessage(*ph_write, *ph_read, (PBYTE)&ipc_handle, sizeof(IPC_HANDLE), NULL, 0);
}

void startParent() {
    CHAR proc_name[MAX_PATH];
    DWORD proc_size = sizeof(proc_name);
    QueryFullProcessImageNameA(GetCurrentProcess(), 0, proc_name, &proc_size);

    PROCESS_INFORMATION pi;
    STARTUPINFOEXA si = { 0 };
    SIZE_T size = 0;
    DWORD64 pol = PROCESS_CREATION_MITIGATION_POLICY_PROHIBIT_DYNAMIC_CODE_ALWAYS_ON;
    si.StartupInfo.cb = sizeof(si);
    InitializeProcThreadAttributeList(NULL, 1, 0, &size);
    si.lpAttributeList = HeapAlloc(GetProcessHeap(), 0, size);
    InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &size);
    UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_MITIGATION_POLICY, &pol, sizeof(pol), NULL, NULL);
    CreateProcessA(proc_name, NULL, NULL, NULL, FALSE, EXTENDED_STARTUPINFO_PRESENT, NULL, NULL, (STARTUPINFO*)&si, &pi);
    HeapFree(GetProcessHeap(), 0, si.lpAttributeList);
}

void childMain() {
    HANDLE h_parent = INVALID_HANDLE_VALUE;
    HANDLE h_read = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE h_write = GetStdHandle(STD_OUTPUT_HANDLE);

    while (TRUE) {
        DWORD read;
        enum IPC_OP op;
        PeekNamedPipe(h_read, &op, sizeof(op), &read, NULL, NULL);
        switch (op) {
            case SEND_HANDLE: {
                IPC_HANDLE ipc_handle = { 0 };
                ReadFile(h_read, &ipc_handle, sizeof(ipc_handle), &read, NULL);
                h_parent = ipc_handle.handle;
                break;
            }
            case CALL: {
                IPC_CALL call = { 0 };
                ReadFile(h_read, &call, sizeof(call), &read, NULL);

                DWORD old_protect = 0;
                BOOL vp_ret = VirtualProtectEx(h_parent, (LPVOID)call.args[0], call.args[1], call.args[2], &old_protect);
                
                DWORD written = 0;
                IPC_VP_RET ipc_vp_ret = { .vp_ret = vp_ret, .old_protect = old_protect };
                WriteFile(h_write, &ipc_vp_ret, sizeof(ipc_vp_ret), &written, NULL);
                break;
            }
        }
    }
}

int main() {
    HANDLE h_write, h_read;
    HANDLE h_sentinel = GetStdHandle(STD_ERROR_HANDLE);

    if (h_sentinel != H_SENTINEL) {
        PROCESS_MITIGATION_DYNAMIC_CODE_POLICY dcp = { 0 };
        GetProcessMitigationPolicy(GetCurrentProcess(), ProcessDynamicCodePolicy, &dcp, sizeof(dcp));
        if (!dcp.ProhibitDynamicCode) {
            startParent();
            return 0;
        }
        startChild(&h_write, &h_read);

        int i = 0;
        while (i < 5) {
            LPVOID alloc = VirtualAlloc(NULL, 1337, MEM_COMMIT, PAGE_READWRITE);
            IPC_VP_RET ret = { 0 };
            IPC_CALL msg = { .op = CALL, .func = VirtualProtect, .argc = 4 };
            msg.args[0] = (UINT_PTR)alloc;
            msg.args[1] = 1337;
            msg.args[2] = PAGE_EXECUTE_READWRITE;
            msg.args[3] = 0;
            sendMessage(h_write, h_read, (PBYTE)&msg, sizeof(msg), (PBYTE)&ret, sizeof(ret));
            i++;
        }
        Sleep(20000);
    }
    else
        childMain();
}
