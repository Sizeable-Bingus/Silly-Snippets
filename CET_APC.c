#include <windows.h>
#include <stdio.h>

// Parasitic gadget

typedef BOOL (WINAPI* QueueUserAPC2_t)(PAPCFUNC ApcRoutine, HANDLE Thread, ULONG_PTR Data, QUEUE_USER_APC_FLAGS Flags);
//   rsi = call target
//   rbx = pointer to final jmp slot   (jmp reads the target from [rbx])
//
//   FF D6   call rsi
//   FF 23   jmp  qword [rbx]
static unsigned char g_stub[] = {
    0xFF, 0xD6,   // call rsi
    0xFF, 0x23,   // jmp [rbx]
};

#define STUB_LEN (sizeof(g_stub))   // 4

typedef struct _STUB_CALL_ARGS {
    UINT_PTR arg1;
    UINT_PTR arg2;
    UINT_PTR arg3;
    UINT_PTR arg4;
} STUB_CALL_ARGS;

typedef struct _STUB_ARG {
  UINT_PTR p_stub;        // 0
  UINT_PTR p_call;        // 8
  UINT_PTR p_jump;        // 16
  UINT_PTR p_rbx;         // 24
  UINT_PTR p_rsi;         // 32
  UINT_PTR p_rdi;         // 40
  UINT_PTR lpFiber;       // 48
  STUB_CALL_ARGS args;    // 56
} STUB_ARG;

__attribute__((naked))
void stubSetup(STUB_ARG* arg) {
    asm(//"sub rsp, 8 \n"
        "sub rsp, 0xA8 \n"
        "mov [rcx + 24], rbx \n"      // save -> p_rbx
        "mov [rcx + 32], rsi \n"      // save -> p_rsi
        "mov [rcx + 40], rdi \n"      // save -> p_rdi

        "mov rdi, rcx \n"             // arg ptr (survives call)
        "lea rbx, [rcx + 16] \n"      // &p_jump ; stub's jmp [rbx] -> stubReturn
        "mov rsi, [rcx + 8] \n"       // p_call

        "mov r11, rcx \n"
        "mov rdx, [rcx + 64] \n"      // arg2
        "mov r8,  [rcx + 72] \n"      // arg3
        "mov r9,  [rcx + 80] \n"      // arg4
        "mov rcx, [rcx + 56] \n"      // arg1

        "jmp [r11] \n");
}

__attribute__((naked))
void stubReturn() {
    asm(//"add rsp, 8\n"
        "add rsp, 0xA8 \n"
        // "mov rcx, [rdi + 48] \n"
        // "call SwitchToFiber\n"

        "mov rbx, [rdi + 24] \n"      // restore p_rbx
        "mov rsi, [rdi + 32] \n"      // restore p_rsi
        "mov rdi, [rdi + 40] \n"      // restore p_rdi

        "ret \n");
}

__attribute__((naked))
void sleepExSetup() {
    asm("mov rcx, 0xffffffff\n"
        "mov rdx, 1\n"
        "jmp SleepEx\n");
}

__attribute__((naked))
void sleepExSetupReturn() {
    asm("add rsp, 0xA8\n"
        "mov rcx, 0xffffffff\n"
        "mov rdx, 1\n"
        "jmp SleepEx\n");
}
__attribute__((naked))
void intteruptStub() {
    asm("mov rcx, 0\n"
        "mov rdx, 0\n"
        "mov r8,  0\n"
        "mov r9,  0\n"
        "jmp MessageBoxA\n");
}

static VOID sleepRoutine(UINT_PTR parameter) {
    while (TRUE) {
        if (SleepEx(INFINITE, TRUE) == WAIT_IO_COMPLETION) continue;
    }
}

static VOID interruptRoutine(UINT_PTR parameter) {
    MessageBoxA(NULL, "Interrupt", "Interrupt", MB_OK);
}

void stitch(HMODULE h_mod, HANDLE h_thread, CONTEXT sleep_context) {
    STUB_CALL_ARGS call_args = { .arg1 = 0, .arg2 = 0, .arg3 = 0, .arg4 = MB_OK };
    STUB_ARG stub_arg = { 
        .p_stub = (UINT_PTR)h_mod,
        .p_call = (UINT_PTR)MessageBoxA,
        .p_jump = (UINT_PTR)sleepExSetupReturn,
        .p_rbx = 0,
        .p_rsi = 0,
        .p_rdi = 0,
        .lpFiber = (UINT_PTR)0,
        .args = call_args,
    };

    printf("[CTX] 0x%llx : 0x%llx\n", sleep_context.Rip, sleep_context.Rsp);
    printf("[+] Queueing APC\n");
    if (!QueueUserAPC2((PAPCFUNC)stubSetup, h_thread, (UINT_PTR)&stub_arg, QUEUE_USER_APC_FLAGS_SPECIAL_USER_APC)) {
        printf("[ERR:GetProcAddress]\n");
    }
    getchar();
    SuspendThread(h_thread);
    SetThreadContext(h_thread, &sleep_context);
    ResumeThread(h_thread);
    getchar();
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

    HMODULE hMod = LoadLibraryA("C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\149.0.4022.62\\msedge_elf.dll");
    if (hMod == NULL) return 1;
    printf("0x%p\n", hMod);
    hMod = (HMODULE)((UINT_PTR)hMod + 0x13CAF);
    printf("0x%p\n", hMod);
    
    DWORD dwOld;
    VirtualProtect(hMod, 4, PAGE_EXECUTE_READWRITE, &dwOld);
    memcpy(hMod, g_stub, 4);
    printf("0x%p\n", hMod);

    HANDLE h_thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)sleepExSetup, NULL, 0, NULL);
    Sleep(500);

    CONTEXT sleep_context = { 0 };
    sleep_context.ContextFlags = CONTEXT_FULL;
    SuspendThread(h_thread);
    GetThreadContext(h_thread, &sleep_context);
    ResumeThread(h_thread);

    stitch(hMod, h_thread, sleep_context);
    stitch(hMod, h_thread, sleep_context);
}
