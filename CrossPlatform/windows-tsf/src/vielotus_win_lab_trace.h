#pragma once

/*
 * ============================================================================
 * Sen Việt (VieLotusIM) — Windows Native Diagnostic Lab Trace Spool
 * ============================================================================
 * - Off by default (~2ns in-memory tick check every 200ms, zero disk I/O).
 * - When enabled by `VieLotusLab.exe` (via `VieLotusLabActiveSessionWnd` or
 *   `%TEMP%\VieLotusLab\active.flag`), delivers structured TSF events to
 *   `VieLotusLab.exe` via `WM_COPYDATA` and `%TEMP%\VieLotusLab\events.log`.
 * - Enforces 30-minute session TTL and hard-blocks password managers & ES_PASSWORD.
 * ============================================================================
 */

#include <windows.h>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

#define VL_WIN_LAB_COPYDATA_MAGIC 0x564C4142UL /* 'VLAB' */
#define VL_WIN_LAB_SESSION_TTL_SEC 1800ULL     /* 30 minutes max TTL */

namespace vielotus_win_lab {

inline uint64_t NowUs() {
    static LARGE_INTEGER s_freq = []() {
        LARGE_INTEGER f{};
        QueryPerformanceFrequency(&f);
        return f;
    }();
    LARGE_INTEGER counter{};
    if (s_freq.QuadPart <= 0 || !QueryPerformanceCounter(&counter)) {
        return GetTickCount64() * 1000ULL;
    }
    return static_cast<uint64_t>((counter.QuadPart * 1000000ULL) / s_freq.QuadPart);
}

inline std::wstring GetSpoolDir() {
    WCHAR tempPath[MAX_PATH] = {0};
    DWORD len = GetTempPathW(MAX_PATH, tempPath);
    if (len == 0 || len >= MAX_PATH) {
        return L"C:\\Windows\\Temp\\VieLotusLab";
    }
    std::wstring dir(tempPath);
    if (!dir.empty() && dir.back() != L'\\' && dir.back() != L'/') {
        dir.push_back(L'\\');
    }
    dir += L"VieLotusLab";
    return dir;
}

inline bool IsProtectedPasswordContext(const std::wstring &lowerExeName) {
    static const LPCWSTR kProtectedExes[] = {
        L"1password.exe",
        L"bitwarden.exe",
        L"keepass.exe",
        L"keepassxc.exe",
        L"lastpass.exe",
        L"dashlane.exe",
        L"enpass.exe",
        L"credentialuibroker.exe",
        L"logonui.exe"
    };
    for (LPCWSTR item : kProtectedExes) {
        if (lowerExeName == item) {
            return true;
        }
    }
    HWND hFocus = GetFocus();
    if (hFocus && IsWindow(hFocus)) {
        LONG_PTR style = GetWindowLongPtrW(hFocus, GWL_STYLE);
        if ((style & ES_PASSWORD) != 0) {
            return true;
        }
    }
    return false;
}

inline bool IsActive(const std::wstring &lowerExeName) {
    static ULONGLONG s_lastCheckMs = 0;
    static bool s_cachedActive = false;

    ULONGLONG nowMs = GetTickCount64();
    if (s_lastCheckMs != 0 && (nowMs - s_lastCheckMs) < 200ULL) {
        if (!s_cachedActive) {
            return false;
        }
        return !IsProtectedPasswordContext(lowerExeName);
    }
    s_lastCheckMs = nowMs;

    // 1. Fast desktop window marker check (works across AppContainer / UWP / Win32)
    if (FindWindowW(L"VieLotusLabActiveSessionWnd", nullptr) != nullptr) {
        s_cachedActive = true;
        return !IsProtectedPasswordContext(lowerExeName);
    }

    // 2. Fallback file flag check (%TEMP%\VieLotusLab\active.flag with 30-min TTL)
    std::wstring flagPath = GetSpoolDir() + L"\\active.flag";
    WIN32_FILE_ATTRIBUTE_DATA fad{};
    if (!GetFileAttributesExW(flagPath.c_str(), GetFileExInfoStandard, &fad) ||
        (fad.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        s_cachedActive = false;
        return false;
    }

    FILETIME nowFt{};
    GetSystemTimeAsFileTime(&nowFt);
    ULARGE_INTEGER uNow{}, uWrite{};
    uNow.LowPart = nowFt.dwLowDateTime;
    uNow.HighPart = nowFt.dwHighDateTime;
    uWrite.LowPart = fad.ftLastWriteTime.dwLowDateTime;
    uWrite.HighPart = fad.ftLastWriteTime.dwHighDateTime;

    if (uNow.QuadPart > uWrite.QuadPart) {
        uint64_t ageSec = (uNow.QuadPart - uWrite.QuadPart) / 10000000ULL;
        if (ageSec > VL_WIN_LAB_SESSION_TTL_SEC) {
            DeleteFileW(flagPath.c_str());
            s_cachedActive = false;
            return false;
        }
    }

    s_cachedActive = true;
    return !IsProtectedPasswordContext(lowerExeName);
}

inline std::string WideToUtf8Safe(const std::wstring &wstr) {
    if (wstr.empty()) return "";
    int len = WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), nullptr, 0, nullptr, nullptr);
    if (len <= 0) return "";
    std::string out(static_cast<size_t>(len), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wstr.data(), static_cast<int>(wstr.size()), &out[0], len, nullptr, nullptr);
    return out;
}

inline void EscapeAsciiInto(const char *src, char *dst, size_t dstSize) {
    if (!dst || dstSize == 0) return;
    if (!src) {
        dst[0] = '\0';
        return;
    }
    size_t j = 0;
    for (size_t i = 0; src[i] != '\0' && j + 2 < dstSize; ++i) {
        unsigned char c = static_cast<unsigned char>(src[i]);
        if (c == '\n') {
            if (j + 3 >= dstSize) break;
            dst[j++] = '\\';
            dst[j++] = 'n';
        } else if (c == '\r') {
            if (j + 3 >= dstSize) break;
            dst[j++] = '\\';
            dst[j++] = 'r';
        } else if (c == '\t') {
            if (j + 3 >= dstSize) break;
            dst[j++] = '\\';
            dst[j++] = 't';
        } else if (c == '"') {
            if (j + 3 >= dstSize) break;
            dst[j++] = '\\';
            dst[j++] = '"';
        } else if (c < 0x20) {
            continue;
        } else {
            dst[j++] = static_cast<char>(c);
        }
    }
    dst[j] = '\0';
}

inline void WriteEvent(
    const std::wstring &lowerExeName,
    const char *eventType,
    uint64_t elapsedUs,
    const char *fmt,
    ...
) {
    if (!IsActive(lowerExeName)) {
        return;
    }

    SYSTEMTIME st{};
    GetLocalTime(&st);

    char payload[1400] = {0};
    va_list args;
    va_start(args, fmt);
    vsnprintf(payload, sizeof(payload), fmt, args);
    va_end(args);

    std::string exeUtf8 = WideToUtf8Safe(lowerExeName.empty() ? L"unknown.exe" : lowerExeName);
    char safeExe[48] = {0};
    EscapeAsciiInto(exeUtf8.c_str(), safeExe, sizeof(safeExe));

    char line[1900] = {0};
    int len = snprintf(
        line,
        sizeof(line),
        "[%02u:%02u:%02u.%03u] %-14s [ctx:%-16.16s] %-10s (%4llu us) | %s\r\n",
        static_cast<unsigned>(st.wHour),
        static_cast<unsigned>(st.wMinute),
        static_cast<unsigned>(st.wSecond),
        static_cast<unsigned>(st.wMilliseconds),
        "win32-tsf",
        safeExe,
        eventType ? eventType : "EVENT",
        static_cast<unsigned long long>(elapsedUs),
        payload
    );
    if (len <= 0) {
        return;
    }
    size_t bytesToWrite = (static_cast<size_t>(len) < sizeof(line)) ? static_cast<size_t>(len) : (sizeof(line) - 1);

    // 1. Deliver live via WM_COPYDATA if VieLotusLab GUI window is open
    bool deliveredViaCopyData = false;
    HWND hLabWnd = FindWindowW(L"VieLotusLabWindowClass", nullptr);
    if (hLabWnd && IsWindow(hLabWnd)) {
        COPYDATASTRUCT cds{};
        cds.dwData = VL_WIN_LAB_COPYDATA_MAGIC;
        cds.cbData = static_cast<DWORD>(bytesToWrite + 1);
        cds.lpData = line;
        DWORD_PTR msgRes = 0;
        if (SendMessageTimeoutW(
                hLabWnd,
                WM_COPYDATA,
                0,
                reinterpret_cast<LPARAM>(&cds),
                SMTO_ABORTIFHUNG | SMTO_NORMAL,
                40,
                &msgRes
            ) != 0 && msgRes != 0) {
            deliveredViaCopyData = true;
        }
    }

    // 2. If not already persisted by VieLotusLab GUI, append to %TEMP%\VieLotusLab\events.log
    if (!deliveredViaCopyData) {
        std::wstring spoolDir = GetSpoolDir();
        CreateDirectoryW(spoolDir.c_str(), nullptr);
        std::wstring logPath = spoolDir + L"\\events.log";
        HANDLE hFile = CreateFileW(
            logPath.c_str(),
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr
        );
        if (hFile != INVALID_HANDLE_VALUE) {
            DWORD written = 0;
            WriteFile(hFile, line, static_cast<DWORD>(bytesToWrite), &written, nullptr);
            CloseHandle(hFile);
        }
    }
}

} // namespace vielotus_win_lab
