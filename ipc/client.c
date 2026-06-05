#include <windows.h>
#include <stdio.h>
#include "ipc.h"

// Be careful to send valid pointer across processes
ULONG_PTR massDriver(HANDLE hPipe, LPVOID lpFunction, DWORD dwArgc, ...) {
    va_list args;
    FUNCITON_CALL call = {0};
    DWORD dwBytesWritten = 0;
    BOOL bResult = FALSE;
    DWORD dwBytesRead = 0;
    ULONG_PTR ret = 0;

    call.lpFunction = (FUNC_PTR)lpFunction;
    call.dwArgc = dwArgc;

    va_start(args, dwArgc);
    for (DWORD i = 0; i < dwArgc; i++) {
        call.args[i] = va_arg(args, ULONG_PTR);
    }
    va_end(args);

    bResult = WriteFile(hPipe, &call, sizeof(FUNCITON_CALL), &dwBytesWritten, NULL);
    if (bResult) printf("[+] Sent %lu\n", dwBytesWritten);
    else {
        printf("[!] Faild to send data\n");
        return 2;
    }
    
    bResult = ReadFile(hPipe, &ret, sizeof(ret), &dwBytesRead, NULL);
    if (bResult) {
        printf("[+] Recieved 0x%llx\n", ret);
    } else {
        printf("[!] Failed to read : 0x%lx\n", GetLastError());
    }

    return ret;
}

int main() {
    HANDLE hPipe = CreateFileA(PIPE_NAME, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hPipe == INVALID_HANDLE_VALUE) {
        printf("[!] Failed to connec to named pipe\n");
        return 1;
    }

    LPVOID lpAlloc = (LPVOID)massDriver(hPipe, VirtualAlloc, 4, NULL, 0x1234, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);


    DisconnectNamedPipe(hPipe);
    CloseHandle(hPipe);
    return 0;
}
