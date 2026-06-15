#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <processthreadsapi.h>
#include <psapi.h>
#include <dbghelp.h>

#include <array>
#include <cstdlib>
#include <format>
#include <print>
#include <iostream>
#include <memory>
#include <string_view>

namespace {

struct HandleDeleter {
    void operator()(HANDLE handle) const noexcept {
        if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
            CloseHandle(handle);
        }
    }
};

using UniqueHandle = std::unique_ptr<void, HandleDeleter>;

[[nodiscard]] UniqueHandle open_process(DWORD access, DWORD pid) {
    return UniqueHandle{OpenProcess(access, FALSE, pid)};
}

[[nodiscard]] UniqueHandle open_thread(DWORD access, DWORD tid) {
    return UniqueHandle{OpenThread(access, FALSE, tid)};
}

[[noreturn]] void die(std::string_view api) {
    std::cerr << std::format("[ERR:{}] {}\n", api, GetLastError());
    std::exit(EXIT_FAILURE);
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << std::format("usage: {} <pid> <tid>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const auto pid = static_cast<DWORD>(std::strtoul(argv[1], nullptr, 10));
    const auto tid = static_cast<DWORD>(std::strtoul(argv[2], nullptr, 10));

    auto process = open_process(PROCESS_ALL_ACCESS, pid);
    if (!process) {
        die("OpenProcess");
    }

    if (!SymInitialize(process.get(), nullptr, TRUE)) {
        die("SymInitialize");
    }

    auto thread = open_thread(THREAD_ALL_ACCESS, tid);
    if (!thread) {
        die("OpenThread");
    }

    if (SuspendThread(thread.get()) == static_cast<DWORD>(-1)) {
        die("SuspendThread");
    }

    CONTEXT ctx{};
    ctx.ContextFlags = CONTEXT_FULL;
    if (!GetThreadContext(thread.get(), &ctx)) {
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
                         process.get(),
                         thread.get(),
                         &frame,
                         &ctx,
                         nullptr,
                         SymFunctionTableAccess64,
                         SymGetModuleBase64,
                         nullptr))
            break;

        const auto address = frame.AddrPC.Offset;
        if (address == 0) break;

        //auto* symbol = static_cast<PSYMBOL_INFO>(
        alignas(SYMBOL_INFO) std::array<CHAR, (sizeof(SYMBOL_INFO) + (MAX_PATH + 1) * sizeof(CHAR))> symbol_buff{};
        auto* symbol = reinterpret_cast<PSYMBOL_INFO>(symbol_buff.data());
        symbol->MaxNameLen = MAX_PATH;
        symbol->SizeOfStruct = sizeof(SYMBOL_INFO);

        DWORD64 disp{};
        IMAGEHLP_MODULE64 mod{};
        mod.SizeOfStruct = sizeof(mod);
        if (SymFromAddr(process.get(), address, &disp, symbol)) {
            if (SymGetModuleInfo64(process.get(), address, &mod))
                std::println("{}!{}+0x{:x}", mod.ModuleName, symbol->Name, disp);
            else
                std::println("<UNKNOWN>!{}+0x{:x}", symbol->Name, disp);
        } else {
            if (SymGetModuleInfo64(process.get(), address, &mod))
                std::println("{}+{:#x}", mod.ModuleName, address - mod.BaseOfImage);
            else
                std::println("{:#x}", address);
        }
    }
    SymCleanup(process.get());
    ResumeThread(thread.get());
    return EXIT_SUCCESS;
}
