#include <windows.h>
#include <ntstatus.h>
#include <stdio.h>


typedef BOOL (WINAPI* QueueUserAPC2_t)(PAPCFUNC ApcRoutine, HANDLE Thread, ULONG_PTR Data, QUEUE_USER_APC_FLAGS Flags);
typedef NTSTATUS (NTAPI* NtGetNextThread_t)(
    _In_ HANDLE ProcessHandle,
    _In_opt_ HANDLE ThreadHandle,
    _In_ ACCESS_MASK DesiredAccess,
    _In_ ULONG HandleAttributes,
    _In_opt_ _Reserved_ ULONG Flags,
    _Out_ PHANDLE NewThreadHandle
    );

#define STUB_LEN (sizeof(g_stub))   // 4

__attribute__((naked))
void sleepExSetup() {
    __asm("mov rcx, 0xffffffff\n"
        "mov rdx, 1\n"
        "jmp SleepEx\n");
}

__attribute__((naked))
void intteruptStub(PAPC_CALLBACK_DATA data) {
    __asm(
        "mov r10, [rcx]\n"     // Parameter
        "mov r11, [rcx + 8]\n" // ContextRecord
        
        //"mov qword ptr [r11 + 0x4F0], 0\n"
        "mov qword ptr [r11 +0x78], 0x101\n" // Have RtlDelayExecution return with STATUS_ALERTED

        "mov rcx, 0\n"
        "mov rdx, 0\n"
        "mov r8,  0\n"
        "mov r9,  0\n"
        "jmp MessageBoxA\n");
}

void stitch(HANDLE h_thread) {
    printf("[+] Queueing APC\n");
    if (!QueueUserAPC2((PAPCFUNC)intteruptStub, h_thread, 0, QUEUE_USER_APC_FLAGS_SPECIAL_USER_APC | QUEUE_USER_APC_CALLBACK_DATA_CONTEXT)) {
        printf("[ERR:GetProcAddress]\n");
    }
    getchar();
}

NTSTATUS enumThreads(HANDLE h_proc) {
    NtGetNextThread_t NtGetNextThread = (NtGetNextThread_t)GetProcAddress(
        GetModuleHandle("ntdll.dll"),
        "NtGetNextThread"
    );
    if (NtGetNextThread == NULL) {
        printf("[ERR:GetProcAddress]\n");
        return 1;
    }

    NTSTATUS status = STATUS_SUCCESS;
    HANDLE h_thread = NULL;
    status = NtGetNextThread(h_proc, NULL, READ_CONTROL, 0, 0, &h_thread);
    if (status != STATUS_SUCCESS) return status;

    while (status != STATUS_NO_MORE_ENTRIES) {
        printf("[enumThreads] 0x%p\n", h_thread);
        status = NtGetNextThread(h_proc, h_thread, READ_CONTROL, 0, 0, &h_thread);
    }
    return status;
}

int main() {
    QueueUserAPC2_t QueueUserAPC2 = (QueueUserAPC2_t)GetProcAddress(
        GetModuleHandle("kernel32.dll"),
        "QueueUserAPC2"
    );
    if (QueueUserAPC2 == NULL) {
        printf("[ERR:GetProcAddress]\n");
        return 1;
    }

    //HANDLE h_thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)sleepExSetup, NULL, 0, NULL);
    //Sleep(500);

    // Avoid thread creation and RtlTimer* in callstack but introduce UB
    // Technically UB but from what I can see RDX is always SleepEx which is true
    // Identifying this thread is tricky...
    HANDLE h_timer = 0;
    QueueUserWorkItem((LPTHREAD_START_ROUTINE)SleepEx, (PVOID)INFINITE, 0);
    getchar();
    enumThreads(GetCurrentProcess());
    return 0;
    
    // stitch(h_thread);
    // stitch(h_thread);
}
