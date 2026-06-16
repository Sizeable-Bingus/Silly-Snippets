#include <windows.h>
#include <stdio.h>

typedef BOOL (WINAPI* QueueUserAPC2_t)(PAPCFUNC ApcRoutine, HANDLE Thread, ULONG_PTR Data, QUEUE_USER_APC_FLAGS Flags);

static VOID sleepRoutine(UINT_PTR parameter) {
    while (true) {
        Sleep(100);
    }
}

static VOID interruptRoutine(UINT_PTR parameter) {
    MessageBoxA(NULL, "Interrupt", "Interrupt", MB_OK);
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

    HANDLE h_thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)sleepRoutine, NULL, 0, NULL);
    getchar();

    printf("[+] Queueing special APC\n");
    if (!QueueUserAPC2(interruptRoutine, h_thread, 0, QUEUE_USER_APC_FLAGS_SPECIAL_USER_APC)) {
        printf("[ERR:GetProcAddress]\n");
        return 2;
    }
    WaitForSingleObject(h_thread, INFINITE);
    CloseHandle(h_thread);
    
    return 0;
}
