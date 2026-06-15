#include <windows.h>
#include <stdio.h>

// Parasitic gadget

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
        "mov rcx, [rdi + 48] \n"
        "call SwitchToFiber\n"

        "mov rbx, [rdi + 24] \n"      // restore p_rbx
        "mov rsi, [rdi + 32] \n"      // restore p_rsi
        "mov rdi, [rdi + 40] \n"      // restore p_rdi

        "ret \n");
}


int main() {

    HMODULE hMod = LoadLibraryA("C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\149.0.4022.62\\msedge_elf.dll");
    if (hMod == NULL) return 1;
    printf("0x%p\n", hMod);
    hMod = (HMODULE)((UINT_PTR)hMod + 0x13CAF);
    printf("0x%p\n", hMod);
    
    DWORD dwOld;
    VirtualProtect(hMod, 4, PAGE_EXECUTE_READWRITE, &dwOld);
    memcpy(hMod, g_stub, 4);
    printf("0x%p\n", hMod);

    LPVOID lpRootFiber = ConvertThreadToFiber(NULL);
    if (lpRootFiber == NULL) {
        printf("NO FIBER\n");
    } else {
        printf("0x%p\n", lpRootFiber);
    }
    STUB_CALL_ARGS call_args = { .arg1 = 0, .arg2 = 0, .arg3 = 0, .arg4 = MB_OK };
    STUB_ARG stub_arg = { 
        .p_stub = (UINT_PTR)hMod,
        .p_call = (UINT_PTR)MessageBoxA,
        .p_jump = (UINT_PTR)stubReturn,
        .p_rbx = 0,
        .p_rsi = 0,
        .p_rdi = 0,
        .lpFiber = (UINT_PTR)lpRootFiber,
        .args = call_args,
    };
    LPVOID p_fiber = CreateFiber(0, (LPFIBER_START_ROUTINE)stubSetup, &stub_arg);
    SwitchToFiber(p_fiber);
    MessageBoxA(NULL, "A", "A", MB_OK);
}
