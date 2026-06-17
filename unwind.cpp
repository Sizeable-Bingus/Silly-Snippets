#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <processthreadsapi.h>
#include <psapi.h>
#include <dbghelp.h>
#include <winternl.h>
#include <ntstatus.h>

#include <array>
#include <vector>
#include <expected>
#include <cstdlib>
#include <format>
#include <print>
#include <iostream>
#include <memory>
#include <string_view>

typedef NTSTATUS (NTAPI* NtGetNextThread_t)(
    _In_ HANDLE ProcessHandle,
    _In_opt_ HANDLE ThreadHandle,
    _In_ ACCESS_MASK DesiredAccess,
    _In_ ULONG HandleAttributes,
    _In_opt_ _Reserved_ ULONG Flags,
    _Out_ PHANDLE NewThreadHandle
    );


namespace {

struct HandleDeleter {
    void operator()(HANDLE handle) const noexcept {
        if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
            CloseHandle(handle);
        }
    }
};


using uniq_handle = std::unique_ptr<void, HandleDeleter>;

struct ProcessThreads {
    HANDLE h_process;
    std::vector<uniq_handle> h_threads;
};


[[noreturn]] void die(std::string_view api) {
    std::cerr << std::format("[ERR:{}] {:#x}\n", api, GetLastError());
    std::exit(EXIT_FAILURE);
}

void print_frame(HANDLE process, DWORD64 address) {
    alignas(SYMBOL_INFO)
    std::array<CHAR, sizeof(SYMBOL_INFO) + (MAX_PATH + 1) * sizeof(CHAR)> symbol_buff{};
    auto* symbol = reinterpret_cast<PSYMBOL_INFO>(symbol_buff.data());
    symbol->MaxNameLen = MAX_PATH;
    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);

    DWORD64 disp{};
    IMAGEHLP_MODULE64 mod{};
    mod.SizeOfStruct = sizeof(mod);
    const bool have_mod = SymGetModuleInfo64(process, address, &mod);

    if (SymFromAddr(process, address, &disp, symbol)) {
        if (have_mod)
            std::println("{}!{}+0x{:x}", mod.ModuleName, symbol->Name, disp);
        else
            std::println("<UNKNOWN>!{}+0x{:x}", symbol->Name, disp);
    } else if (have_mod) {
        std::println("{}+{:#x}", mod.ModuleName, address - mod.BaseOfImage);
    } else {
        std::println("{:#x}", address);
    }
}

std::expected<ProcessThreads, NTSTATUS> enumThreads(HANDLE h_proc) {
    NtGetNextThread_t NtGetNextThread = (NtGetNextThread_t)GetProcAddress(
        GetModuleHandle("ntdll.dll"),
        "NtGetNextThread"
    );
    if (NtGetNextThread == NULL) {
        std::println("[ERR:GetProcAddress]\n");
        return std::unexpected(STATUS_NOT_FOUND);
    }

    NTSTATUS status = STATUS_SUCCESS;
    HANDLE h_thread = NULL;
    status = NtGetNextThread(h_proc, NULL, THREAD_ALL_ACCESS, 0, 0, &h_thread);
    if (status != STATUS_SUCCESS) return std::unexpected(status);

    ProcessThreads process_threads{
        .h_process = h_proc,
        .h_threads{},
    };

    process_threads.h_threads.push_back(uniq_handle{h_thread});
    while (status != STATUS_NO_MORE_ENTRIES) {
        status = NtGetNextThread(h_proc, h_thread, THREAD_ALL_ACCESS, 0, 0, &h_thread);

        if (status == STATUS_SUCCESS) process_threads.h_threads.push_back(uniq_handle{h_thread});
        else if (status != STATUS_SUCCESS && status != STATUS_NO_MORE_ENTRIES) return std::unexpected(status);
    }
    return process_threads;
 
}

std::expected<void, NTSTATUS> enumThreadStacks(ProcessThreads process_threads) {
    for (const auto& h_thread: process_threads.h_threads) {
        auto thread_id = GetThreadId(h_thread.get());
        std::println("\n===================={}====================", thread_id);
        CONTEXT ctx{};
        ctx.ContextFlags = CONTEXT_FULL;
        if (!GetThreadContext(h_thread.get(), &ctx)) {
            die("GetThreadContext");
        }

        STACKFRAME64 frame{};
        frame.AddrPC.Offset = ctx.Rip;
        frame.AddrFrame.Offset = ctx.Rbp;
        frame.AddrStack.Offset = ctx.Rsp;
        frame.AddrPC.Mode = AddrModeFlat;
        frame.AddrFrame.Mode = AddrModeFlat;
        frame.AddrStack.Mode = AddrModeFlat;

        while (true) {
            if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64,
                             process_threads.h_process,
                             h_thread.get(),
                             &frame,
                             &ctx,
                             nullptr,
                             SymFunctionTableAccess64,
                             SymGetModuleBase64,
                             nullptr))
                break;

            const auto address = frame.AddrPC.Offset;
            if (address == 0) break;

            print_frame(process_threads.h_process, address);
        }
        std::println("===================={}====================", thread_id);
    }
    return{};
}


// [[nodiscard]] DWORD64 thread_start_address(HANDLE thread) {
//     using Fn = NTSTATUS(NTAPI*)(HANDLE, THREADINFOCLASS, PVOID, ULONG, PULONG);

//     const auto fn = reinterpret_cast<Fn>(
//         GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationThread"));
//     if (fn == nullptr) {
//         die("GetProcAddress(NtQueryInformationThread)");
//     }

//     PVOID start = nullptr;
//     const NTSTATUS st =
//         fn(thread, ThreadQuerySetWin32StartAddress, &start, sizeof(start), nullptr);
//     if (st < 0) {  // !NT_SUCCESS
//         die("NtQueryInformationThread");
//     }
//     return reinterpret_cast<DWORD64>(start);
// }

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << std::format("usage: {} <pid> <tid>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const auto pid = static_cast<DWORD>(std::strtoul(argv[1], nullptr, 10));
    //const auto tid = static_cast<DWORD>(std::strtoul(argv[2], nullptr, 10));

    const auto process = uniq_handle{OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid)};
    if (!process) {
        die("OpenProcess");
    }

    if (!SymInitialize(process.get(), nullptr, TRUE)) {
        die("SymInitialize");
    }

    if (auto et_ret = enumThreads(process.get()) .and_then(enumThreadStacks); !et_ret)
        die(std::format("enumThreads : {:x}", et_ret.error()));

    SymCleanup(process.get());
    return EXIT_SUCCESS;
}
