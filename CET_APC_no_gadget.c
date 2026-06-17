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
void stubSetup(PAPC_CALLBACK_DATA arg) {
    __asm(//"sub rsp, 8 \n"
        "sub rsp, 0xA8 \n"
        "mov r10, [rcx] \n"
        "mov [r10 + 24], rbx \n"      // save -> p_rbx
        "mov [r10 + 32], rsi \n"      // save -> p_rsi
        "mov [r10 + 40], rdi \n"      // save -> p_rdi

        "mov rdi, r10 \n"             // arg ptr (survives call)
        "lea rbx, [r10 + 16] \n"      // &p_jump ; stub's jmp [rbx] -> stubReturn
        "mov rsi, [r10 + 8] \n"       // p_call

        "mov r11, r10\n"
        "mov rdx, [r10 + 64] \n"      // arg2
        "mov r8,  [r10 + 72] \n"      // arg3
        "mov r9,  [r10 + 80] \n"      // arg4
        "mov rcx, [r10 + 56] \n"      // arg1

        "jmp [r11] \n");
}

__attribute__((naked))
void stubReturn() {
    __asm("add rsp, 0xA8 \n"
        "mov rbx, [rdi + 24] \n"      // restore p_rbx
        "mov rsi, [rdi + 32] \n"      // restore p_rsi
        "mov rdi, [rdi + 40] \n"      // restore p_rdi

        "ret \n");
}

__attribute__((naked))
void sleepExSetup() {
    __asm("mov rcx, 0xffffffff\n"
        "mov rdx, 1\n"
        "jmp SleepEx\n");
}

__attribute__((naked))
void sleepExSetupReturn() {
    __asm("add rsp, 0xA8\n"
        "mov rcx, 0xffffffff\n"
        "mov rdx, 1\n"
        "jmp SleepEx\n");
}

__attribute__((naked))
void intteruptStub(PAPC_CALLBACK_DATA data) {
    __asm(
        "mov r10, [rcx]\n"        // &sleep_context
        "mov r11, [rcx + 8]\n"    // &ContextRecord
        "mov rsi, r10\n"
        "mov rdi, r11\n"
        "mov rcx, 154\n"
        "rep movsq\n"

        //"mov qword ptr [r11 + 0x4F0], 0\n"
        //"mov qword ptr [r11 +0x78], 0x101\n" // Have RtlDelayExecution return with STATUS_ALERTED

        "mov rcx, 0\n"
        "mov rdx, 0\n"
        "mov r8,  0\n"
        "mov r9,  0\n"
        "jmp MessageBoxA\n");
}

static VOID sleepRoutine(PAPC_CALLBACK_DATA data) {
    while (TRUE) {
        if (SleepEx(INFINITE, TRUE) == WAIT_IO_COMPLETION) continue;
    }
}

static VOID interruptRoutine(PAPC_CALLBACK_DATA data) {
    printf("[APC] 0x%llx : 0x%llx", data->ContextRecord->Rip,
                                    data->ContextRecord->Rsp);
    MessageBoxA(NULL, "Interrupt", "Interrupt", MB_OK);
}

typedef struct _INTERRUPT_ARG {
    UINT_PTR Rip;
    UINT_PTR Rsp;
} INTERRUPT_ARG;

void stitch(HMODULE h_mod, HANDLE h_thread, CONTEXT sleep_context) {
    // STUB_CALL_ARGS call_args = { .arg1 = 0, .arg2 = 0, .arg3 = 0, .arg4 = MB_OK };
    // STUB_ARG stub_arg = { 
    //     .p_stub = (UINT_PTR)h_mod,
    //     .p_call = (UINT_PTR)MessageBoxA,
    //     .p_jump = (UINT_PTR)sleepExSetupReturn,
    //     .p_rbx = 0,
    //     .p_rsi = 0,
    //     .p_rdi = 0,
    //     .lpFiber = (UINT_PTR)0,
    //     .args = call_args,
    // };

    //INTERRUPT_ARG arg = { .Rip = sleep_context.Rip, .Rsp = sleep_context.Rsp };
    

    printf("[CTX] 0x%llx : 0x%llx\n", sleep_context.Rip, sleep_context.Rsp);
    printf("[+] Queueing APC\n");
    if (!QueueUserAPC2((PAPCFUNC)intteruptStub, h_thread, (ULONG_PTR)&sleep_context, QUEUE_USER_APC_FLAGS_SPECIAL_USER_APC | QUEUE_USER_APC_CALLBACK_DATA_CONTEXT)) {
        printf("[ERR:GetProcAddress]\n");
    }
    getchar();
    // SuspendThread(h_thread);
    // SetThreadContext(h_thread, &sleep_context);
    // ResumeThread(h_thread);
    // getchar();
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
