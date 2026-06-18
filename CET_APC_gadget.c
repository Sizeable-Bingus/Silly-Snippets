#include <windows.h>
#include <ntstatus.h>
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
    UINT_PTR rbp_save; // 120
    UINT_PTR rbx_save; // 128
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
  __asm("sub rsp, 88\n" // combase gadget frame size

        "mov r10, [rcx]\n"     // INTERRUPT_ARG / function
        "mov r11, [rcx + 8]\n" // ContextRecord

        "mov qword ptr [r10 + 120], rbp\n" // Save rbp
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
        "mov qword ptr [rsp + rcx*8 + 0x28], r8\n"
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
        "lea rbp, [r10 + 96 + 8]\n" // pointer to epilogue
        "sub rbp, rdx\n"

        "mov rcx, [r11]\n"
        "mov rdx, [r11 + 8]\n"
        "mov r8,  [r11 + 16]\n"
        "mov r9,  [r11 + 24]\n"
        "jmp [r10 + 96]\n");
}

__attribute__((naked))
void interruptEpilogue() {
    __asm(
        "add rsp, 88\n"
        "mov rcx, rbx\n"
        "mov rbp, [rcx+120]\n"
        "mov rbx, [rcx+128]\n"
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
    BYTE jmp[2] = { 0xFF, 0x65 };  // jmp [rbp +/- 8_disp]
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

void stitch(HANDLE h_thread) {
    printf("[+] Queueing APC : 0x%p\n", (LPVOID)interuptStub);
    // STARTUPINFO si = { 0 };
    // si.cb = sizeof(si);
    // PROCESS_INFORMATION pi = { 0 };
    // FUNC_CALL func_call = { 0 };
    // func_call.function = (UINT_PTR)CreateProcessA;
    // func_call.argc = 10;
    // func_call.argv[0] = (UINT_PTR)"C:\\Windows\\System32\\calc.exe";
    // func_call.argv[4] = FALSE;
    // func_call.argv[8] = (UINT_PTR)&si;
    // func_call.argv[9] = (UINT_PTR)&pi;
    
    
// CreateProcessA(LPCSTR lpApplicationName,
// LPSTR lpCommandLine,
// LPSECURITY_ATTRIBUTES lpProcessAttributes,
// LPSECURITY_ATTRIBUTES lpThreadAttributes,
// WINBOOL bInheritHandles,
// DWORD dwCreationFlags,
// LPVOID lpEnvironment,
// LPCSTR lpCurrentDirectory,
// LPSTARTUPINFOA lpStartupInfo,
// LPPROCESS_INFORMATION lpProcessInformation)

    HMODULE h_combase = GetModuleHandleA("combase.dll");
    if (h_combase == NULL) h_combase = LoadLibraryA("combase.dll");
    GADGET gadget = { 0 };
    findGadget(h_combase, &gadget);

    FUNC_CALL call = { 0 };
    call.function = (UINT_PTR)MessageBoxA;
    call.argc = 4;
    call.argv[0] = 0;
    call.argv[1] = 0;
    call.argv[3] = 0;
    call.argv[4] = 0;
    INTERRUPT_ARG arg = { .gadget = gadget, .func_call = call };

    printf("[ARG] FUNC_CALL : %llu\tGADGET : %llu\trbp_save : %llu\n", offsetof(INTERRUPT_ARG, func_call), offsetof(INTERRUPT_ARG, gadget), offsetof(INTERRUPT_ARG, rbp_save));
    if (!QueueUserAPC2((PAPCFUNC)interuptStub, h_thread, (ULONG_PTR)&arg, QUEUE_USER_APC_FLAGS_SPECIAL_USER_APC | QUEUE_USER_APC_CALLBACK_DATA_CONTEXT)) {
        printf("[ERR:QueueUserAPC2] : 0x%lx\n", GetLastError());
    }
    getchar();
}

int main() {
    // QueueUserAPC2_t QueueUserAPC2 = (QueueUserAPC2_t)GetProcAddress(
    //     GetModuleHandle("kernel32.dll"),
    //     "QueueUserAPC2"
    // );
    // if (QueueUserAPC2 == NULL) {
    //     printf("[ERR:GetProcAddress]\n");

    HANDLE h_thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)sleepExSetup, NULL, 0, NULL);
    Sleep(500);

    // // Avoid thread creation and RtlTimer* in callstack but introduce UB
    // // Technically UB but from what I can see RDX is always SleepEx which is true
    // // Identifying this thread is tricky...
    // HANDLE h_timer = 0;
    // // QueueUserWorkItem((LPTHREAD_START_ROUTINE)SleepEx, (PVOID)INFINITE, 0);
    // // getchar();
    // // enumThreads(GetCurrentProcess());

    // stitch(h_thread);
    // stitch(h_thread);

    HMODULE h_combase = LoadLibraryA("combase.dll");
    if (h_combase == NULL) {
        printf("ERR\n");
        return 1;
    }

    printf("0x%p\n", interuptStub);
    getchar();
    stitch(h_thread);

    //offsetof(INTERRUPT_ARG, func_call);

    getchar();

    return 0;
}
