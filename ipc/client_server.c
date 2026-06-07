#include <windows.h>
#include <stdio.h>
#include "ipc.h"

/*
 * Attempt to connect
 * If no allocator process start one
*/

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

INT client(HANDLE hPipe) {
    //HANDLE hPipe = CreateFileA(PIPE_NAME, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    //if (hPipe == INVALID_HANDLE_VALUE) {
    //    printf("[!] Failed to connect to named pipe\n");
    //    return 1;
    //}

    LPVOID lpAlloc = (LPVOID)massDriver(hPipe, VirtualAlloc, 4, NULL, 0x1234, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    CloseHandle(hPipe);
    return 0;
}

INT server(HANDLE hPipe) {
    //HANDLE hPipe = CreateNamedPipeA(PIPE_NAME, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE, 1, 0, 0, 0, NULL);
    //if (hPipe == NULL || hPipe == INVALID_HANDLE_VALUE) {
    //    printf("[!] Failed to create named pipe\n");
    //    return 1;
    //}

    printf("[+:Server] Waiting for client\n");
    BOOL result = ConnectNamedPipe(hPipe, NULL);
    if (!result && GetLastError() != ERROR_PIPE_CONNECTED) {
        printf("[!] Failed to connect named pipe (err %lu)\n", GetLastError());
        CloseHandle(hPipe);
        return 2;
    }

    printf("[+:Server] Client connected, reading...\n");
    FUNCITON_CALL buffer = { 0 };
    DWORD dwBytesRead = 0;
    result = ReadFile(hPipe, (PBYTE)&buffer, sizeof(buffer), &dwBytesRead, NULL);
    if (result) {
        printf("[+Server] Read %lu / %llu\n", dwBytesRead, sizeof(FUNCITON_CALL));
        printf("[+Server] 0x%p ( %llu, %llu, %llu, %llu )", buffer.lpFunction, buffer.args[0], buffer.args[1], buffer.args[2], buffer.args[3]);
        ULONG_PTR ret = buffer.lpFunction(
                buffer.args[0], buffer.args[1], 
                buffer.args[2], buffer.args[3], 
                buffer.args[4], buffer.args[5], 
                buffer.args[6], buffer.args[7], 
                buffer.args[8], buffer.args[9]
                );
        DWORD dwBytesWritten = 0;
        BOOL bResult = WriteFile(hPipe, &ret, sizeof(ULONG_PTR), &dwBytesWritten, NULL);
        if (bResult) printf("[+:Server] Wrote : 0x%llx\n", ret);
    }

    DisconnectNamedPipe(hPipe);
    CloseHandle(hPipe);
    return 0;
}

HANDLE StartServerChild(PCHAR exe) {
    PCHAR cmd = strcat(exe, " 1");
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    BOOL bProc = CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi);
    if (!bProc) {
        printf("[ERROR] CreateProcessA : 0x%lX\n", GetLastError());
        return (HANDLE)-2;
    }
    Sleep(1000); // TODO
    return CreateFileA(
            PIPE_NAME,
            GENERIC_READ | GENERIC_WRITE, 
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            NULL,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            NULL);
}

int main(int argc, char* argv[]) {
    if (argc > 1) {
        printf("[+] Server\n");
        HANDLE hPipe = CreateNamedPipeA(PIPE_NAME, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE, 1, 0, 0, 0, NULL);
        if (hPipe == INVALID_HANDLE_VALUE) {
            printf("[ERROR] CreateNamedPipeA : 0x%lX", GetLastError());
            return 1;
        }
        return server(hPipe);
    } else {
        HANDLE hPipe = CreateFileA(
                PIPE_NAME,
                GENERIC_READ | GENERIC_WRITE, 
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                NULL,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                NULL);
        if (hPipe == INVALID_HANDLE_VALUE && GetLastError() == ERROR_FILE_NOT_FOUND)
            hPipe = StartServerChild(argv[0]);
        if (hPipe == INVALID_HANDLE_VALUE) {
            printf("[ERROR] StartServerChild : 0%lX\n", GetLastError());
            return 2;
        }
        return client(hPipe);
    }

    //HANDLE hPipe = CreateNamedPipeA(PIPE_NAME, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE, 1, 0, 0, 0, NULL);
    //if (hPipe == INVALID_HANDLE_VALUE) {
    //    DWORD dwErr = GetLastError();
    //    if (dwErr == ERROR_PIPE_BUSY) {
    //        hPipe = CreateFileA(PIPE_NAME, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    //        if (hPipe == INVALID_HANDLE_VALUE) {
    //            printf("[!] Failed to open named pipe : 0x%lX\n", GetLastError());
    //            return 1;
    //        }
    //        return client(hPipe);
    //    } else {
    //        printf("[!] Failed to create named pipe : 0x%lX\n", dwErr);
    //        return 1;
    //    }
    //}
    //server(hPipe);
}
