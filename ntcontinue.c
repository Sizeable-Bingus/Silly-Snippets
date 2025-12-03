#include <windows.h>
#include <stdio.h>

HANDLE gDoneEvent = NULL;

typedef NTSTATUS (NTAPI* ftNtContinue) (PCONTEXT ThreadContext, BOOLEAN RaiseAlert);
ftNtContinue NtContinue = NULL;


//VOID CALLBACK TimerRoutine(PVOID lpParam, BOOLEAN TimerOrWaitFired)
VOID CALLBACK TimerRoutine()
{
    printf("BRUH\n");
    SetEvent(gDoneEvent);
}

int main() {
    HANDLE hTimer = NULL;
    HANDLE hTimerContext = NULL;
    HANDLE hTimerQueue = NULL;
    int arg = 123;
    
    NtContinue = (ftNtContinue)GetProcAddress(GetModuleHandleA("ntdll"), "NtContinue");
    if (NtContinue == NULL) {
        printf("API Not Resolved\n");
        return -1;
    }

    gDoneEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
    if (gDoneEvent == NULL) {
        printf("CreateEvent failed (%lu)\n", GetLastError());
        return 1;
    }

    hTimerQueue = CreateTimerQueue();
    if (NULL == hTimerQueue) {
        printf("CreateTimerQueue failed (%lu)\n", GetLastError());
        return 2;
    }

    getchar();
    CONTEXT context = { 0 };
    RtlCaptureContext(&context);
    context.Rip = (ULONG_PTR)TimerRoutine;
    //context.Rcx = (ULONG_PTR)NULL;
    //context.Rdx = (ULONG_PTR)FALSE;
    context.Rsp -= sizeof(PVOID); //Why is this needed? (I am retarded)
    printf("%llx : %llx : %llx\n", context.Rip, context.Rcx, context.Rdx);
    printf("%p\n", NtContinue);
    NtContinue(&context, FALSE);
    
   // if (!CreateTimerQueueTimer(&hTimer, hTimerQueue, (WAITORTIMERCALLBACK)RtlCaptureContext, &context, 10000, 0, 0)) {
   //     printf("CreateTimerQueueTimer failed (%lu)\n", GetLastError());
   //     return 3;
   // } 

   // //if (WaitForSingleObject(hTimer, INFINITE) != WAIT_OBJECT_0)
   // //    printf("WaitForSingleObject failed (%lu)\n", GetLastError());
   // Sleep(11000);
   // 
   // printf("%llx : %llx : %llx\n", context.Rip, context.Rcx, context.Rdx);
   // context.Rip = (ULONG_PTR)TimerRoutine;

   // if (!CreateTimerQueueTimer(&hTimer, hTimerQueue, (WAITORTIMERCALLBACK)NtContinue, &context, 10000, 0, 0)) {
   //     printf("CreateTimerQueueTimer failed (%lu)\n", GetLastError());
   //     return 3;
   // }

   // printf("Call timer routine in 10 seconds...\n");

   // if (WaitForSingleObject(gDoneEvent, INFINITE) != WAIT_OBJECT_0)
   //     printf("WaitForSingleObject failed (%lu)\n", GetLastError());

   // printf("Routine done\n");

    CloseHandle(gDoneEvent);

    // Delete all timers in the timer queue.
    if (!DeleteTimerQueue(hTimerQueue))
        printf("DeleteTimerQueue failed (%lu)\n", GetLastError());

    printf("Returning");
    return 0;
}
