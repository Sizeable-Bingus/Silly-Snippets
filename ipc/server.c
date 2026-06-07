#include <windows.h>
#include <stdio.h>
#include "ipc.h"

int main() {
    HANDLE hPipe = CreateNamedPipeA(PIPE_NAME, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE, 1, 0, 0, 0, NULL);
    if (hPipe == NULL || hPipe == INVALID_HANDLE_VALUE) {
        printf("[!] Failed to create named pipe 0x%lX\n", GetLastError());
        return 1;
    }

    printf("[+] Waiting for client\n");
    BOOL result = ConnectNamedPipe(hPipe, NULL);
    if (!result && GetLastError() != ERROR_PIPE_CONNECTED) {
        printf("[!] Failed to connect named pipe (err %lu)\n", GetLastError());
        CloseHandle(hPipe);
        return 2;
    }

    printf("[+] Client connected, reading...\n");
    FUNCITON_CALL buffer = { 0 };
    DWORD dwBytesRead = 0;
    result = ReadFile(hPipe, (PBYTE)&buffer, sizeof(buffer), &dwBytesRead, NULL);
    if (result) {
        printf("[+] Read %lu / %llu\n", dwBytesRead, sizeof(FUNCITON_CALL));
        printf("[+] 0x%p ( %llu, %llu, %llu, %llu )", buffer.lpFunction, buffer.args[0], buffer.args[1], buffer.args[2], buffer.args[3]);
        ULONG_PTR ret = buffer.lpFunction(
                buffer.args[0], buffer.args[1], 
                buffer.args[2], buffer.args[3], 
                buffer.args[4], buffer.args[5], 
                buffer.args[6], buffer.args[7], 
                buffer.args[8], buffer.args[9]
                );
        DWORD dwBytesWritten = 0;
        BOOL bResult = WriteFile(hPipe, &ret, sizeof(ULONG_PTR), &dwBytesWritten, NULL);
        if (bResult) printf("[+] Wrote : 0x%llx\n", ret);
        getchar();
    }

    DisconnectNamedPipe(hPipe);
    CloseHandle(hPipe);
    return 0;
}
