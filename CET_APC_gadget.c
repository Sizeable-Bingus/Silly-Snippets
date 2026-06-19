#include <windows.h>
#include <stdio.h>
#include <stddef.h>
#include "unwind.h"

// This *should* work for any callback/execution that comes from a clean base, not just APC2
// CreateThread from unbacked is not usally a huge deal, CreateTread targeting unbacked is usually more scrutinized.
//     CFG really hurts this approach though (if GetInjectedThreadEx)

// TODO: getFrameSize funciton
// TODO: retry until suitable gadget is found

typedef BOOL (WINAPI* QueueUserAPC2_t)(PAPCFUNC ApcRoutine, HANDLE Thread, ULONG_PTR Data, QUEUE_USER_APC_FLAGS Flags);

typedef struct _FUNC_CALL {
    UINT_PTR function;
    UINT_PTR argc;
    UINT_PTR argv[10];
} FUNC_CALL, PFUNC_CALL;

typedef struct _GADGET {
    LPVOID call;            // 0
    UINT_PTR disp_scratch;  // 8
    UINT_PTR frame_size;    // 16
    INT32 call_disp;        // 24
    INT8 jmp_disp;          // 28
} GADGET, *PGADGET;

typedef struct _INTERRUPT_ARG {
    FUNC_CALL func_call;
    GADGET gadget;
    UINT_PTR rsi_save; // 128
    UINT_PTR rbx_save; // 136
    UINT_PTR ret;      // 144
    HANDLE   h_done;   // 152
} INTERRUPT_ARG, *PINTERRUPT_ARG;

typedef struct {
    DWORD size;
    BOOL pushed_rbp;
    ULONG code_count;
    BOOL sets_fp;
} STACK_FRAME;

enum ERROR_LEVEL {
    log,
    error,
};

// This is wonky
void dlog(enum ERROR_LEVEL err_level, PCHAR func_name, BOOL get_last_err, PCHAR fmt, ...) {
    DWORD err = GetLastError();
    va_list print_va;

    va_start(print_va, fmt);
    int msg_len = vsnprintf(NULL, 0, fmt, print_va);
    va_end(print_va);
    if (msg_len < 0) return;

    PCHAR msg_buf = malloc(msg_len + 1);
    va_start(print_va, fmt);
    vsnprintf(msg_buf, msg_len + 1, fmt, print_va);
    va_end(print_va);

    PCHAR err_lvl_str = NULL;
    if (err_level == log) err_lvl_str = "DBG";
    else if (err_level == error) err_lvl_str = "ERROR";

   
    if (get_last_err) {
        LPSTR err_msg = NULL;
        DWORD len = FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM, NULL, err, LANG_SYSTEM_DEFAULT, (LPSTR)&err_msg, 0, NULL);
        err_msg[len-3] = '\0';
        printf("[%s][%s][%s] -> %s", err_lvl_str, func_name, err_msg, msg_buf);
        LocalFree(err_msg);
    }
    else printf("[%s][%s] -> %s", err_lvl_str, func_name, msg_buf);
    free(msg_buf);
}

#ifdef WIN_X64
__attribute__((naked))
void sleepExSetup() {
    __asm("mov rcx, 0xffffffff\n"
        "mov rdx, 1\n"
        "jmp SleepEx\n");
}

__attribute__((naked))
void interuptStub(PAPC_CALLBACK_DATA data) {
  __asm(
        "mov r10, [rcx]\n"                         // INTERRUPT_ARG / function
        "mov r11, [rcx + 8]\n"                     // ContextRecord
        "mov qword ptr [r10 + 128], rsi\n"         // Save rsi
        "mov qword ptr [r10 + 136], rbx\n"         // Save rbx
        "mov rbx, r10\n"                           // Store INTERRUPT_ARG for epilogue

        "sub rsp, [r10 + 96 + 16]\n"               //gadget frame size



        //"mov qword ptr [r11 + 0x4F0], 0\n"
        "mov qword ptr [r11 + 0x78], 0x101\n"      // Have RtlDelayExecution return with STATUS_ALERTED to it will reenter

        "lea r11, [r10 + 16]\n"                    // &argv

        "mov rax, [r10 + 8]\n"                     // argc
        "dec rax\n"                                // 0 indexing
        "mov rcx, rax\n"                           // stack offset
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
        "mov rcx, r10\n"                           // pointer to target function, needs call displacement
        "movsxd rdx, dword ptr [r10 + 96 + 24]\n"  // call displacement
        "lea rax, [rcx]\n"                         // pointer to function pointer
        "sub rax, rdx\n"                           // apply displacement

        "movsx rdx, byte ptr [r10 + 96 + 28]\n"    // jmp displacement
        "lea rsi, [r10 + 96 + 8]\n"                // pointer to epilogue
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
        "mov rcx, rbx\n"
        "add rsp, [rcx+96+16]\n"
        "mov rsi, [rcx+128]\n"
        "mov rbx, [rcx+136]\n"
        "mov qword ptr [rcx+144], rax\n"

        "mov rdx, [rcx+152]\n"
        "mov rcx, rdx\n"
        "call SetEvent\n"
        "ret\n"
    );
}

PRUNTIME_FUNCTION getRuntimeFunction(LPVOID address, PDWORD64 p_image_base) {
    DWORD64 image_base = 0;
    UNWIND_HISTORY_TABLE history_table = { 0 };
    PRUNTIME_FUNCTION p_runtime_function = RtlLookupFunctionEntry((DWORD64)address, &image_base, &history_table);
    if (p_runtime_function == NULL) {
        dlog(error, "getRuntimeFunction", FALSE, "RtlLookupFunctionEntry failed\n");
    }
    if (p_image_base != NULL) *p_image_base = image_base;
    return p_runtime_function;
}

// Does not include return (using call gadget)
DWORD getFrameSize(PRUNTIME_FUNCTION p_runtime_function, DWORD64 image_base) {
    UBYTE i = 0;
    STACK_FRAME frame = { 0 };
    PUNWIND_INFO p_unwind_info = (PUNWIND_INFO)(p_runtime_function->UnwindData + image_base);
    for (; i < p_unwind_info->CountOfCodes; i++) {
        ULONG unwind_op = p_unwind_info->UnwindCode[i].UnwindOp;
        ULONG op_info = p_unwind_info->UnwindCode[i].OpInfo;

        switch (unwind_op) {
            case UWOP_PUSH_NONVOL:
                frame.size += 8;
                if (op_info == RBP_OP_INFO) {
                    frame.pushed_rbp = TRUE;
                    frame.code_count = p_unwind_info->CountOfCodes;
                }
                break;
            case UWOP_SAVE_NONVOL:
                i += 1;
                break;
            case UWOP_ALLOC_SMALL:
                frame.size += ((op_info * 8) + 8);
                break;
            case UWOP_ALLOC_LARGE:
                i += 1;
                ULONG frame_offset = p_unwind_info->UnwindCode[i].FrameOffset;
                if (op_info == 0) frame_offset *= 8;
                else {
                    i += 1;
                    frame_offset += (p_unwind_info->UnwindCode[i].FrameOffset << 16);
                }
                frame.size += frame_offset;
            case UWOP_SET_FPREG:
                frame.sets_fp = TRUE;
                break;
            case UWOP_SAVE_XMM128:
                i += 1;
                break;
            case UWOP_SAVE_XMM128_FAR:
                i += 2;
                break;
            default:
                break;
        }
    }

    if ((p_unwind_info->Flags & UNW_FLAG_CHAININFO) != 0) {
        i = p_unwind_info->CountOfCodes;
        if ((i & 1) != 0) i += 1;
        p_runtime_function = (PRUNTIME_FUNCTION)(&p_unwind_info->UnwindCode[i]);
        return getFrameSize(p_runtime_function, image_base);
    }

    //frame.size += 8;

    return frame.size;
}

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
    dlog(log, "findGadget", FALSE, "0x%llx 0x%llx\n", text_start, text_end);
    for (PBYTE i = (PBYTE)text_start; (UINT_PTR)i < text_end; i++) {
        if (memcmp(i, call, 2) == 0 && memcmp(i+6, jmp, 2) == 0) {
            PRUNTIME_FUNCTION p_runtime_func = getRuntimeFunction(i, NULL);
            if (p_runtime_func == NULL) {
                dlog(log, "findGadget", FALSE, "Could not get RUNTIME_FUNCTION for 0x%p\n", i);
                continue;
            }
            gadget->call = i;
            gadget->frame_size = getFrameSize(p_runtime_func, (DWORD64)h_module);
            gadget->disp_scratch = (UINT_PTR)interruptEpilogue;
            gadget->call_disp = *(PINT32)(i+2);
            gadget->jmp_disp = *(PINT8)(i+8);

            dlog(log, "findGadget", FALSE, "0x%p : %d : 0x%x : 0x%llx\n", i, gadget->call_disp, gadget->jmp_disp, gadget->frame_size);
            return TRUE;
        }
    }
    return FALSE;
}
#endif


// Dont pass a struct by value to this
UINT_PTR stitch(HANDLE h_thread, LPVOID function, DWORD argc, ...) {
    dlog(log, "stitch", FALSE, "Queueing APC : 0x%p\n", (LPVOID)interuptStub);
    FUNC_CALL func_call = { 0 };
    func_call.function = (UINT_PTR)function;
    func_call.argc = argc;
    va_list args;
    va_start(args, argc);
    for (DWORD i = 0; i < argc; i++) {
        func_call.argv[i] = va_arg(args, UINT_PTR);
    }
    va_end(args);
    
    HMODULE h_mod = NULL;
    GADGET gadget = { 0 };
    PCHAR modules[] = { "ucrtbasee", "msvcrte", "kernelbasee", "ntdlle" };
    dlog(log, "stitch", FALSE, "%lld modules\n", sizeof(modules)/sizeof(PCHAR));
    for (int i = 0; i < sizeof(modules)/sizeof(PCHAR); i++) {
        h_mod = GetModuleHandleA(modules[i]);
        if (h_mod == NULL) continue;

        if (!findGadget(h_mod, &gadget)) dlog(log, "stitch", FALSE, "Could not find gadget in %s\n", modules[i]);
        else {
            dlog(log, "stitch", FALSE, "Found gadget in %s\n", modules[i]);
            break;
        }
    } if (gadget.call == 0) {
        dlog(error, "stitch", FALSE, "Could not locate gadget in module list\n");
        return -1;
    }

    HANDLE h_done = CreateEvent(NULL, TRUE, FALSE, NULL);
    INTERRUPT_ARG arg = { .gadget = gadget, .func_call = func_call, .h_done = h_done };

    if (!QueueUserAPC2((PAPCFUNC)interuptStub, (HANDLE)-4, (ULONG_PTR)&arg, QUEUE_USER_APC_FLAGS_SPECIAL_USER_APC | QUEUE_USER_APC_CALLBACK_DATA_CONTEXT)) {
        dlog(error, "stitch", TRUE, "QueueUserAPC2 failed\n");
        return -1;
    }
    WaitForSingleObject(h_done, INFINITE);
    return arg.ret;
}

int main() {
    dlog(log, "main", FALSE, "FUNC_CALL : %llu\tGADGET : %llu\trsi_save : %llu\n", offsetof(INTERRUPT_ARG, func_call), offsetof(INTERRUPT_ARG, gadget), offsetof(INTERRUPT_ARG, rsi_save));

    HANDLE h_thread = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)sleepExSetup, NULL, 0, NULL);
    Sleep(100);

    dlog(log, "main", FALSE, "0x%p\n", interuptStub);


    STARTUPINFO si = { 0 };
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = { 0 };
    BOOL b_createprocess = (BOOL)stitch(h_thread, CreateProcessA, 10, "C:\\Windows\\System32\\calc.exe", NULL, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi);
    dlog(log, "main", FALSE, "stitch(CreateProcessA) : 0x%x\n", b_createprocess);

    return 0;
}
