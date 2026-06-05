#pragma once

#include <windows.h>

#define PIPE_NAME "\\\\.\\pipe\\silly"

typedef ULONG_PTR (*FUNC_PTR)(ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR, ULONG_PTR);

typedef struct _FUNCTION_CALL {
    FUNC_PTR lpFunction;
    DWORD dwArgc;
    ULONG_PTR args[10];
} FUNCITON_CALL, *PFUNCITON_CALL;

