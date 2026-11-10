#include <windows.h>
#include <msctf.h>
#include <shellapi.h>
#include <shlobj.h>
#include <strsafe.h>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>
#include "vielotus_win_lab_trace.h"

#ifndef TF_PROFILETYPE_INPUTPROCESSOR
#define TF_PROFILETYPE_INPUTPROCESSOR 1
#endif
#ifndef MSGFLT_ALLOW
#define MSGFLT_ALLOW 1
#endif

static const CLSID kClsidVieLotusTIP = {
    0xc7b08e9d, 0x4762, 0x4c97, { 0x8b, 0x1f, 0x52, 0x21, 0x97, 0xa5, 0x98, 0xdc }
};
static const GUID kGuidVieLotusTelex = {
    0x8e2a7b44, 0x5a1f, 0x4b82, { 0x9b, 0x7c, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc }
};
static const GUID kGuidVieLotusVni = {
    0x8e2a7b45, 0x5a1f, 0x4b82, { 0x9b, 0x7c, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc }
};
static const GUID kGuidTfCatTipKeyboard = {
    0x34745c63, 0xb2f0, 0x4784, { 0x8b, 0x67, 0x5e, 0x12, 0xc8, 0x70, 0x1a, 0x31 }
};

enum {
    IDC_BTN_TOGGLE_TRACE = 2001,
    IDC_BTN_FIX_TSF      = 2002,
    IDC_BTN_SELFTEST     = 2003,
    IDC_BTN_COPY_REPORT  = 2004,
    IDC_BTN_CLEAR_LOG    = 2005,
    IDC_EDIT_TEST_INPUT  = 2006,
    IDC_EDIT_LOG_VIEW    = 2007,
    IDT_POLL_TIMER       = 3001
};

struct LabAppState {
    HWND hMainWnd{nullptr};
    HWND hActiveMarkerWnd{nullptr};
    HWND hStatusStatic{nullptr};
    HWND hBtnToggle{nullptr};
    HWND hBtnFixTsf{nullptr};
    HWND hBtnSelfTest{nullptr};
    HWND hBtnCopyReport{nullptr};
    HWND hBtnClear{nullptr};
    HWND hTestLabel{nullptr};
    HWND hTestEdit{nullptr};
    HWND hLogEdit{nullptr};
    HFONT hUiFont{nullptr};
    HFONT hBoldFont{nullptr};
    HFONT hMonoFont{nullptr};
    bool isRecording{false};
    DWORD lastLogFileSize{0};
    float dpiScale{1.0f};
};

static LabAppState g_app{};

static std::wstring Utf8ToWideStr(const std::string &utf8) {
    if (utf8.empty()) return L"";
    int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    if (wlen <= 0) return L"";
    std::wstring out(static_cast<size_t>(wlen), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), &out[0], wlen);
    return out;
}

static std::wstring GetExeDirectory() {
    WCHAR buf[MAX_PATH] = {0};
    DWORD len = GetModuleFileNameW(nullptr, buf, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return L"";
    for (int i = static_cast<int>(len) - 1; i >= 0; --i) {
        if (buf[i] == L'\\' || buf[i] == L'/') {
            buf[i] = L'\0';
            break;
        }
    }
    return std::wstring(buf);
}

static std::wstring FindVieLotusTipDllPath(std::wstring &outRegisteredPath) {
    outRegisteredPath.clear();
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            L"SOFTWARE\\Classes\\CLSID\\{C7B08E9D-4762-4C97-8B1F-522197A598DC}\\InprocServer32",
            0,
            KEY_READ | KEY_WOW64_64KEY,
            &hKey
        ) == ERROR_SUCCESS && hKey) {
        WCHAR pathBuf[MAX_PATH] = {0};
        DWORD cb = sizeof(pathBuf);
        DWORD type = 0;
        if (RegQueryValueExW(hKey, nullptr, nullptr, &type, reinterpret_cast<LPBYTE>(pathBuf), &cb) == ERROR_SUCCESS) {
            outRegisteredPath = pathBuf;
        }
        RegCloseKey(hKey);
    }
    if (!outRegisteredPath.empty() && GetFileAttributesW(outRegisteredPath.c_str()) != INVALID_FILE_ATTRIBUTES) {
        return outRegisteredPath;
    }
    std::wstring localDll = GetExeDirectory() + L"\\VieLotusTIP.dll";
    if (GetFileAttributesW(localDll.c_str()) != INVALID_FILE_ATTRIBUTES) {
        return localDll;
    }
    std::wstring pfDll = L"C:\\Program Files\\VieLotusIM\\VieLotusTIP.dll";
    if (GetFileAttributesW(pfDll.c_str()) != INVALID_FILE_ATTRIBUTES) {
        return pfDll;
    }
    return L"";
}

static void AppendLogWide(const std::wstring &wText) {
    if (!g_app.hLogEdit || wText.empty()) return;
    int len = GetWindowTextLengthW(g_app.hLogEdit);
    if (len > 240000) {
        SetWindowTextW(g_app.hLogEdit, L"");
        len = 0;
    }
    SendMessageW(g_app.hLogEdit, EM_SETSEL, static_cast<WPARAM>(len), static_cast<LPARAM>(len));
    SendMessageW(g_app.hLogEdit, EM_REPLACESEL, FALSE, reinterpret_cast<LPARAM>(wText.c_str()));
    SendMessageW(g_app.hLogEdit, EM_SCROLLCARET, 0, 0);
}

static void AppendLogUtf8Line(const char *utf8Line) {
    if (!utf8Line || utf8Line[0] == '\0') return;
    std::string s(utf8Line);
    if (s.size() >= 1 && s.back() == '\n' && (s.size() < 2 || s[s.size() - 2] != '\r')) {
        s.pop_back();
        s += "\r\n";
    } else if (s.back() != '\n') {
        s += "\r\n";
    }
    AppendLogWide(Utf8ToWideStr(s));

    // Also persist to %TEMP%\VieLotusLab\events.log
    std::wstring spoolDir = vielotus_win_lab::GetSpoolDir();
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
        WriteFile(hFile, s.data(), static_cast<DWORD>(s.size()), &written, nullptr);
        LARGE_INTEGER fsize{};
        if (GetFileSizeEx(hFile, &fsize)) {
            g_app.lastLogFileSize = static_cast<DWORD>(fsize.QuadPart);
        }
        CloseHandle(hFile);
    }
}

static std::wstring QueryTsfAndSystemStatusSummary() {
#if defined(_M_ARM64) || defined(__aarch64__)
    const wchar_t *archStr = L"ARM64";
#elif defined(_M_X64) || defined(__x86_64__)
    const wchar_t *archStr = L"x64";
#else
    const wchar_t *archStr = L"x86";
#endif

    std::wstring regDll;
    std::wstring resolvedDll = FindVieLotusTipDllPath(regDll);
    bool dllExists = !resolvedDll.empty() && (GetFileAttributesW(resolvedDll.c_str()) != INVALID_FILE_ATTRIBUTES);

    HKL hkl = GetKeyboardLayout(0);
    unsigned hklVal = static_cast<unsigned>(reinterpret_cast<uintptr_t>(hkl) & 0xFFFFFFFFu);
    unsigned langId = hklVal & 0xFFFFu;

    std::wstring activeProfileStr = L"Chưa kích hoạt / Bàn phím khác";
    ITfInputProcessorProfiles *pProfiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&pProfiles))) && pProfiles) {
        ITfInputProcessorProfileMgr *pMgr = nullptr;
        if (SUCCEEDED(pProfiles->QueryInterface(IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pMgr))) && pMgr) {
            TF_INPUTPROCESSORPROFILE prof{};
            if (SUCCEEDED(pMgr->GetActiveProfile(kGuidTfCatTipKeyboard, &prof))) {
                if (IsEqualCLSID(prof.clsid, kClsidVieLotusTIP)) {
                    if (IsEqualGUID(prof.guidProfile, kGuidVieLotusTelex)) {
                        activeProfileStr = L"Sen Việt — Telex (Đang hoạt động ✓)";
                    } else if (IsEqualGUID(prof.guidProfile, kGuidVieLotusVni)) {
                        activeProfileStr = L"Sen Việt — VNI (Đang hoạt động ✓)";
                    } else {
                        activeProfileStr = L"Sen Việt — Profile khác";
                    }
                } else {
                    WCHAR clsidBuf[64] = {0};
                    StringFromGUID2(prof.clsid, clsidBuf, 64);
                    WCHAR tmp[160] = {0};
                    StringCchPrintfW(tmp, 160, L"Bàn phím khác (lang=0x%04X, clsid=%s)", prof.langid, clsidBuf);
                    activeProfileStr = tmp;
                }
            }
            pMgr->Release();
        }
        pProfiles->Release();
    }

    DWORD vnEnabled = 1, inputMethod = 0, smartBi = 1, senFlex = 1;
    HKEY hPrefs = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\VieLotusIM", 0, KEY_READ, &hPrefs) == ERROR_SUCCESS && hPrefs) {
        DWORD cb = sizeof(DWORD);
        RegQueryValueExW(hPrefs, L"VietnameseEnabled", nullptr, nullptr, reinterpret_cast<LPBYTE>(&vnEnabled), &cb);
        cb = sizeof(DWORD);
        RegQueryValueExW(hPrefs, L"InputMethod", nullptr, nullptr, reinterpret_cast<LPBYTE>(&inputMethod), &cb);
        cb = sizeof(DWORD);
        RegQueryValueExW(hPrefs, L"SmartBilingual", nullptr, nullptr, reinterpret_cast<LPBYTE>(&smartBi), &cb);
        cb = sizeof(DWORD);
        RegQueryValueExW(hPrefs, L"SenFlexProfile", nullptr, nullptr, reinterpret_cast<LPBYTE>(&senFlex), &cb);
        RegCloseKey(hPrefs);
    }

    WCHAR summary[1024] = {0};
    StringCchPrintfW(
        summary,
        1024,
        L"• Kiến trúc: %s  |  HKL hiện tại: 0x%08X (%s)  |  TSF Profile: %s\r\n"
        L"• HKLM InprocServer32: %s (%s)\r\n"
        L"• Cấu hình Registry: VietnameseEnabled=%u, Kiểu gõ=%s, SmartBilingual=%u, SenFlex=%u",
        archStr,
        hklVal,
        (langId == 0x042A) ? L"Tiếng Việt 0x042A ✓" : L"Tiếng Anh / Khác — bấm 'Kích hoạt & Sửa TSF'",
        activeProfileStr.c_str(),
        regDll.empty() ? L"(Chưa đăng ký HKLM)" : regDll.c_str(),
        dllExists ? L"Tồn tại ✓" : L"Không tìm thấy DLL ✗",
        vnEnabled,
        (inputMethod == 1) ? L"VNI" : L"Telex",
        smartBi,
        senFlex
    );
    return std::wstring(summary);
}

static void RefreshStatusHeader() {
    if (!g_app.hStatusStatic) return;
    std::wstring s = QueryTsfAndSystemStatusSummary();
    SetWindowTextW(g_app.hStatusStatic, s.c_str());
}

static void StartTraceRecording() {
    std::wstring spoolDir = vielotus_win_lab::GetSpoolDir();
    CreateDirectoryW(spoolDir.c_str(), nullptr);

    // Grant AppContainer Read/Write ACLs so UWP / WinUI 3 / Edge can also write events.log
    std::wstring icaclsArgs = L"\"" + spoolDir + L"\" /grant \"*S-1-15-2-1:(OI)(CI)(M)\" /grant \"*S-1-15-2-2:(OI)(CI)(M)\" /T /C /Q";
    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpFile = L"icacls.exe";
    sei.lpParameters = icaclsArgs.c_str();
    sei.nShow = SW_HIDE;
    if (ShellExecuteExW(&sei) && sei.hProcess) {
        WaitForSingleObject(sei.hProcess, 2000);
        CloseHandle(sei.hProcess);
    }

    std::wstring flagPath = spoolDir + L"\\active.flag";
    HANDLE hFlag = CreateFileW(flagPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hFlag != INVALID_HANDLE_VALUE) {
        const char kTag[] = "ACTIVE\n";
        DWORD written = 0;
        WriteFile(hFlag, kTag, sizeof(kTag) - 1, &written, nullptr);
        CloseHandle(hFlag);
    }

    if (!g_app.hActiveMarkerWnd) {
        g_app.hActiveMarkerWnd = CreateWindowExW(
            0,
            L"VieLotusLabActiveSessionWnd",
            L"VieLotusLabActiveSession",
            WS_POPUP,
            0, 0, 0, 0,
            nullptr, nullptr, GetModuleHandleW(nullptr), nullptr
        );
    }

    g_app.isRecording = true;
    if (g_app.hBtnToggle) {
        SetWindowTextW(g_app.hBtnToggle, L"■ Dừng ghi Trace (Đang ghi...)");
    }
    AppendLogWide(L"[LAB] === Đã BẮT ĐẦU ghi Trace TSF (Hãy gõ thử vào ô bên trên hoặc sang Notepad/Chrome) ===\r\n");
}

static void StopTraceRecording() {
    if (g_app.hActiveMarkerWnd) {
        DestroyWindow(g_app.hActiveMarkerWnd);
        g_app.hActiveMarkerWnd = nullptr;
    }
    std::wstring flagPath = vielotus_win_lab::GetSpoolDir() + L"\\active.flag";
    DeleteFileW(flagPath.c_str());
    g_app.isRecording = false;
    if (g_app.hBtnToggle) {
        SetWindowTextW(g_app.hBtnToggle, L"● Bắt đầu ghi Trace");
    }
    AppendLogWide(L"[LAB] === Đã DỪNG ghi Trace TSF ===\r\n");
}

static void RunFixAndActivateTsf() {
    AppendLogWide(L"[LAB] Đang kiểm tra và kích hoạt TSF Profile + HKL Tiếng Việt (0x042A)...\r\n");
    std::wstring regDll;
    std::wstring dllPath = FindVieLotusTipDllPath(regDll);
    if (dllPath.empty()) {
        AppendLogWide(L"[LAB] ✗ LỖI: Không tìm thấy VieLotusTIP.dll trong HKLM hoặc thư mục hiện tại!\r\n");
        return;
    }

    HMODULE hDll = LoadLibraryW(dllPath.c_str());
    if (!hDll) {
        WCHAR msg[256] = {0};
        StringCchPrintfW(msg, 256, L"[LAB] ✗ LỖI: LoadLibraryW(%s) thất bại (err=%lu)\r\n", dllPath.c_str(), GetLastError());
        AppendLogWide(msg);
        return;
    }

    using PFN_RundllEntryW = void(CALLBACK *)(HWND, HINSTANCE, LPWSTR, int);
    auto pfnAct = reinterpret_cast<PFN_RundllEntryW>(GetProcAddress(hDll, "ActivateUserProfilesW"));
    if (pfnAct) {
        pfnAct(g_app.hMainWnd, hDll, const_cast<LPWSTR>(L""), SW_SHOW);
        AppendLogWide(L"[LAB] ✓ Đã gọi ActivateUserProfilesW thành công.\r\n");
    }
    FreeLibrary(hDll);

    HKL hklVi = LoadKeyboardLayoutW(L"0000042a", KLF_ACTIVATE | KLF_SUBSTITUTE_OK);
    if (hklVi) {
        ActivateKeyboardLayout(hklVi, KLF_SETFORPROCESS);
        SendMessageW(g_app.hMainWnd, WM_INPUTLANGCHANGEREQUEST, 0, reinterpret_cast<LPARAM>(hklVi));
        if (g_app.hTestEdit) {
            SendMessageW(g_app.hTestEdit, WM_INPUTLANGCHANGEREQUEST, 0, reinterpret_cast<LPARAM>(hklVi));
        }
        WCHAR msg[160] = {0};
        StringCchPrintfW(msg, 160, L"[LAB] ✓ Đã chuyển HKL sang 0x%08X (Tiếng Việt 0x042A).\r\n",
                         static_cast<unsigned>(reinterpret_cast<uintptr_t>(hklVi) & 0xFFFFFFFFu));
        AppendLogWide(msg);
    }

    RefreshStatusHeader();
    if (g_app.hTestEdit) {
        SetFocus(g_app.hTestEdit);
    }
}

static void RunEngineSelfTest() {
    AppendLogWide(L"[LAB] --- Chạy kiểm thử trực tiếp lõi Engine trong VieLotusTIP.dll ---\r\n");
    std::wstring regDll;
    std::wstring dllPath = FindVieLotusTipDllPath(regDll);
    if (dllPath.empty()) {
        AppendLogWide(L"[LAB] ✗ Không tìm thấy VieLotusTIP.dll để kiểm thử.\r\n");
        return;
    }

    HMODULE hDll = LoadLibraryW(dllPath.c_str());
    if (!hDll) {
        AppendLogWide(L"[LAB] ✗ Không thể nạp VieLotusTIP.dll.\r\n");
        return;
    }

    using pfn_create = void *(*)(void);
    using pfn_destroy = void (*)(void *);
    using pfn_feed = int32_t (*)(void *, uint32_t);
    using pfn_bs = int32_t (*)(void *);
    using pfn_text = const char *(*)(void *);

    auto create_session = reinterpret_cast<pfn_create>(GetProcAddress(hDll, "vielotus_create_session"));
    auto destroy_session = reinterpret_cast<pfn_destroy>(GetProcAddress(hDll, "vielotus_destroy_session"));
    auto feed_char = reinterpret_cast<pfn_feed>(GetProcAddress(hDll, "vielotus_feed_char"));
    auto get_bs = reinterpret_cast<pfn_bs>(GetProcAddress(hDll, "vielotus_get_last_backspaces"));
    auto get_text = reinterpret_cast<pfn_text>(GetProcAddress(hDll, "vielotus_get_last_text"));

    if (!create_session || !destroy_session || !feed_char || !get_bs || !get_text) {
        AppendLogWide(L"[LAB] ✗ VieLotusTIP.dll thiếu hàm C-ABI kiểm thử.\r\n");
        FreeLibrary(hDll);
        return;
    }

    struct TestCase {
        const char *keys;
        const wchar_t *expected;
    };
    static const TestCase kCases[] = {
        { "vieets ", L"việt " },
        { "tiengs ", L"tiếng " },
        { "truowngr ", L"trưởng " },
        { "dduowcj ", L"được " },
        { "window user ", L"window user " }
    };

    void *sess = create_session();
    int passed = 0;
    for (const auto &tc : kCases) {
        std::wstring screen;
        for (const char *p = tc.keys; *p; ++p) {
            uint32_t cp = static_cast<uint32_t>(static_cast<unsigned char>(*p));
            int32_t act = feed_char(sess, cp);
            if (act == 3 /* COMMIT */) {
                int32_t bs = get_bs(sess);
                if (bs > 0 && static_cast<size_t>(bs) <= screen.size()) {
                    screen.resize(screen.size() - static_cast<size_t>(bs));
                }
                const char *txt = get_text(sess);
                screen += Utf8ToWideStr(txt ? txt : "");
                screen.push_back( static_cast<wchar_t>(cp) );
            } else if (act == 2 /* REPLACE */) {
                int32_t bs = get_bs(sess);
                if (bs > 0 && static_cast<size_t>(bs) <= screen.size()) {
                    screen.resize(screen.size() - static_cast<size_t>(bs));
                }
                const char *txt = get_text(sess);
                screen += Utf8ToWideStr(txt ? txt : "");
            } else {
                screen.push_back(static_cast<wchar_t>(cp));
            }
        }
        bool ok = (screen == tc.expected);
        if (ok) ++passed;
        WCHAR line[256] = {0};
        StringCchPrintfW(
            line,
            256,
            L"[SELF-TEST] %s: input=\"%S\" -> output=\"%s\" (expected=\"%s\")\r\n",
            ok ? L"PASS ✓" : L"FAIL ✗",
            tc.keys,
            screen.c_str(),
            tc.expected
        );
        AppendLogWide(line);
    }
    destroy_session(sess);
    FreeLibrary(hDll);

    WCHAR summary[128] = {0};
    StringCchPrintfW(summary, 128, L"[LAB] Kết quả Self-Test Engine: %d/5 PASS.\r\n", passed);
    AppendLogWide(summary);
}

static void CopyMarkdownReportToClipboard() {
    RefreshStatusHeader();
    std::wstring statusText = QueryTsfAndSystemStatusSummary();

    WCHAR testBuf[1024] = {0};
    if (g_app.hTestEdit) {
        GetWindowTextW(g_app.hTestEdit, testBuf, 1020);
    }

    int logLen = g_app.hLogEdit ? GetWindowTextLengthW(g_app.hLogEdit) : 0;
    std::wstring logText;
    if (logLen > 0) {
        logText.resize(static_cast<size_t>(logLen) + 1, L'\0');
        GetWindowTextW(g_app.hLogEdit, &logText[0], logLen + 1);
        logText.resize(wcslen(logText.c_str()));
    }

    std::wstring report = L"### Báo cáo Chẩn đoán Sen Việt (VieLotusLab Windows)\r\n\r\n";
    report += L"#### 1. Trạng thái Hệ thống & TSF\r\n```text\r\n";
    report += statusText;
    report += L"\r\n```\r\n\r\n#### 2. Nội dung Ô Gõ Thử\r\n```text\r\n";
    report += testBuf;
    report += L"\r\n```\r\n\r\n#### 3. Nhật ký Keystroke Trace\r\n```text\r\n";
    report += logText;
    report += L"```\r\n";

    if (OpenClipboard(g_app.hMainWnd)) {
        EmptyClipboard();
        size_t cb = (report.size() + 1) * sizeof(WCHAR);
        HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, cb);
        if (hMem) {
            void *ptr = GlobalLock(hMem);
            if (ptr) {
                memcpy(ptr, report.c_str(), cb);
                GlobalUnlock(hMem);
                SetClipboardData(CF_UNICODETEXT, hMem);
            }
        }
        CloseClipboard();
        AppendLogWide(L"[LAB] ✓ Đã sao chép toàn bộ Báo cáo Markdown vào Clipboard (Hãy nhấn Ctrl+V để gửi)!\r\n");
    }
}

static void PollExternalLogFile() {
    if (!g_app.isRecording) return;
    std::wstring logPath = vielotus_win_lab::GetSpoolDir() + L"\\events.log";
    HANDLE hFile = CreateFileW(
        logPath.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );
    if (hFile == INVALID_HANDLE_VALUE) return;

    LARGE_INTEGER fsize{};
    if (GetFileSizeEx(hFile, &fsize)) {
        DWORD curSize = static_cast<DWORD>(fsize.QuadPart);
        if (curSize > g_app.lastLogFileSize) {
            DWORD diff = curSize - g_app.lastLogFileSize;
            if (diff > 65536) {
                g_app.lastLogFileSize = curSize - 65536;
                diff = 65536;
            }
            SetFilePointer(hFile, static_cast<LONG>(g_app.lastLogFileSize), nullptr, FILE_BEGIN);
            std::vector<char> buf(diff + 1, '\0');
            DWORD readBytes = 0;
            if (ReadFile(hFile, buf.data(), diff, &readBytes, nullptr) && readBytes > 0) {
                buf[readBytes] = '\0';
                AppendLogWide(Utf8ToWideStr(std::string(buf.data(), readBytes)));
            }
            g_app.lastLogFileSize = curSize;
        } else if (curSize < g_app.lastLogFileSize) {
            g_app.lastLogFileSize = curSize;
        }
    }
    CloseHandle(hFile);
}

static void LayoutChildren(HWND hwnd, int width, int height) {
    float s = g_app.dpiScale;
    int pad = static_cast<int>(12.0f * s);
    int statusH = static_cast<int>(64.0f * s);
    int btnY = pad + statusH + static_cast<int>(8.0f * s);
    int btnH = static_cast<int>(32.0f * s);
    int availW = width - pad * 2;

    if (g_app.hStatusStatic) {
        MoveWindow(g_app.hStatusStatic, pad, pad, availW, statusH, TRUE);
    }

    int gap = static_cast<int>(6.0f * s);
    int btnW = (availW - gap * 4) / 5;
    if (g_app.hBtnToggle)     MoveWindow(g_app.hBtnToggle,     pad + (btnW + gap) * 0, btnY, btnW, btnH, TRUE);
    if (g_app.hBtnFixTsf)     MoveWindow(g_app.hBtnFixTsf,     pad + (btnW + gap) * 1, btnY, btnW, btnH, TRUE);
    if (g_app.hBtnSelfTest)   MoveWindow(g_app.hBtnSelfTest,   pad + (btnW + gap) * 2, btnY, btnW, btnH, TRUE);
    if (g_app.hBtnCopyReport) MoveWindow(g_app.hBtnCopyReport, pad + (btnW + gap) * 3, btnY, btnW, btnH, TRUE);
    if (g_app.hBtnClear)      MoveWindow(g_app.hBtnClear,      pad + (btnW + gap) * 4, btnY, availW - (btnW + gap) * 4, btnH, TRUE);

    int testY = btnY + btnH + static_cast<int>(10.0f * s);
    int testH = static_cast<int>(28.0f * s);
    int labelW = static_cast<int>(140.0f * s);
    if (g_app.hTestLabel) {
        MoveWindow(g_app.hTestLabel, pad, testY + static_cast<int>(4.0f * s), labelW, testH, TRUE);
    }
    if (g_app.hTestEdit) {
        MoveWindow(g_app.hTestEdit, pad + labelW, testY, availW - labelW, testH, TRUE);
    }

    int logY = testY + testH + static_cast<int>(10.0f * s);
    int logH = height - logY - pad;
    if (logH < 60) logH = 60;
    if (g_app.hLogEdit) {
        MoveWindow(g_app.hLogEdit, pad, logY, availW, logH, TRUE);
    }
}

static LRESULT CALLBACK LabWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE: {
        g_app.hMainWnd = hwnd;
        HDC hdc = GetDC(hwnd);
        int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
        ReleaseDC(hwnd, hdc);
        g_app.dpiScale = (dpiY > 0) ? (static_cast<float>(dpiY) / 96.0f) : 1.0f;
        float s = g_app.dpiScale;

        // Allow WM_COPYDATA from lower integrity / AppContainer processes
        HMODULE hUser32 = GetModuleHandleW(L"user32.dll");
        if (hUser32) {
            using PFN_ChangeWindowMessageFilterEx = BOOL(WINAPI *)(HWND, UINT, DWORD, PCHANGEFILTERSTRUCT);
            auto pfnFilter = reinterpret_cast<PFN_ChangeWindowMessageFilterEx>(
                GetProcAddress(hUser32, "ChangeWindowMessageFilterEx")
            );
            if (pfnFilter) {
                pfnFilter(hwnd, WM_COPYDATA, MSGFLT_ALLOW, nullptr);
            }
        }

        g_app.hUiFont = CreateFontW(
            -static_cast<int>(12.5f * s + 0.5f), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_SWISS, L"Segoe UI"
        );
        g_app.hBoldFont = CreateFontW(
            -static_cast<int>(13.0f * s + 0.5f), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_SWISS, L"Segoe UI"
        );
        g_app.hMonoFont = CreateFontW(
            -static_cast<int>(12.0f * s + 0.5f), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            FIXED_PITCH | FF_MODERN, L"Consolas"
        );

        g_app.hStatusStatic = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"STATIC", L"",
            WS_CHILD | WS_VISIBLE | SS_LEFT,
            0, 0, 100, 50, hwnd, nullptr, GetModuleHandleW(nullptr), nullptr
        );
        g_app.hBtnToggle = CreateWindowExW(
            0, L"BUTTON", L"● Bắt đầu ghi Trace",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 100, 30, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_BTN_TOGGLE_TRACE)), GetModuleHandleW(nullptr), nullptr
        );
        g_app.hBtnFixTsf = CreateWindowExW(
            0, L"BUTTON", L"⚡ Kích hoạt & Sửa TSF",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 100, 30, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_BTN_FIX_TSF)), GetModuleHandleW(nullptr), nullptr
        );
        g_app.hBtnSelfTest = CreateWindowExW(
            0, L"BUTTON", L"🧪 Kiểm thử Engine",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 100, 30, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_BTN_SELFTEST)), GetModuleHandleW(nullptr), nullptr
        );
        g_app.hBtnCopyReport = CreateWindowExW(
            0, L"BUTTON", L"📋 Sao chép Báo cáo",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 100, 30, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_BTN_COPY_REPORT)), GetModuleHandleW(nullptr), nullptr
        );
        g_app.hBtnClear = CreateWindowExW(
            0, L"BUTTON", L"🗑 Xoá Log",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 100, 30, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_BTN_CLEAR_LOG)), GetModuleHandleW(nullptr), nullptr
        );

        g_app.hTestLabel = CreateWindowExW(
            0, L"STATIC", L"✦ Ô gõ thử trực tiếp:",
            WS_CHILD | WS_VISIBLE | SS_LEFT,
            0, 0, 100, 24, hwnd, nullptr, GetModuleHandleW(nullptr), nullptr
        );
        g_app.hTestEdit = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            0, 0, 100, 28, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_EDIT_TEST_INPUT)), GetModuleHandleW(nullptr), nullptr
        );
        SendMessageW(
            g_app.hTestEdit, 0x1501 /* EM_SETCUEBANNER */, TRUE,
            reinterpret_cast<LPARAM>(L"Gõ thử tại đây: vieets -> việt | tiengs -> tiếng | truowngr -> trưởng...")
        );

        g_app.hLogEdit = CreateWindowExW(
            WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_AUTOHSCROLL | ES_READONLY,
            0, 0, 100, 100, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_EDIT_LOG_VIEW)), GetModuleHandleW(nullptr), nullptr
        );
        SendMessageW(g_app.hLogEdit, EM_SETLIMITTEXT, 512000, 0);

        HWND uiCtrls[] = {
            g_app.hStatusStatic, g_app.hBtnToggle, g_app.hBtnFixTsf,
            g_app.hBtnSelfTest, g_app.hBtnCopyReport, g_app.hBtnClear, g_app.hTestEdit
        };
        for (HWND hCtrl : uiCtrls) {
            if (hCtrl && g_app.hUiFont) {
                SendMessageW(hCtrl, WM_SETFONT, reinterpret_cast<WPARAM>(g_app.hUiFont), TRUE);
            }
        }
        if (g_app.hTestLabel && g_app.hBoldFont) {
            SendMessageW(g_app.hTestLabel, WM_SETFONT, reinterpret_cast<WPARAM>(g_app.hBoldFont), TRUE);
        }
        if (g_app.hLogEdit && g_app.hMonoFont) {
            SendMessageW(g_app.hLogEdit, WM_SETFONT, reinterpret_cast<WPARAM>(g_app.hMonoFont), TRUE);
        }

        RECT rc{};
        GetClientRect(hwnd, &rc);
        LayoutChildren(hwnd, rc.right - rc.left, rc.bottom - rc.top);

        // Reset previous log file size tracker & auto-start recording + self-test
        std::wstring logPath = vielotus_win_lab::GetSpoolDir() + L"\\events.log";
        DeleteFileW(logPath.c_str());
        g_app.lastLogFileSize = 0;

        RefreshStatusHeader();
        StartTraceRecording();
        RunEngineSelfTest();
        RunFixAndActivateTsf();

        SetTimer(hwnd, IDT_POLL_TIMER, 400, nullptr);
        return 0;
    }

    case WM_SIZE: {
        LayoutChildren(hwnd, LOWORD(lParam), HIWORD(lParam));
        return 0;
    }

    case WM_TIMER: {
        if (wParam == IDT_POLL_TIMER) {
            PollExternalLogFile();
            RefreshStatusHeader();
        }
        return 0;
    }

    case WM_COPYDATA: {
        const auto *cds = reinterpret_cast<const COPYDATASTRUCT *>(lParam);
        if (cds && cds->dwData == VL_WIN_LAB_COPYDATA_MAGIC && cds->lpData && cds->cbData > 0) {
            const char *line = static_cast<const char *>(cds->lpData);
            AppendLogUtf8Line(line);
            return 1;
        }
        return 0;
    }

    case WM_COMMAND: {
        switch (LOWORD(wParam)) {
        case IDC_BTN_TOGGLE_TRACE:
            if (g_app.isRecording) {
                StopTraceRecording();
            } else {
                StartTraceRecording();
            }
            return 0;
        case IDC_BTN_FIX_TSF:
            RunFixAndActivateTsf();
            return 0;
        case IDC_BTN_SELFTEST:
            RunEngineSelfTest();
            return 0;
        case IDC_BTN_COPY_REPORT:
            CopyMarkdownReportToClipboard();
            return 0;
        case IDC_BTN_CLEAR_LOG: {
            if (g_app.hLogEdit) SetWindowTextW(g_app.hLogEdit, L"");
            if (g_app.hTestEdit) SetWindowTextW(g_app.hTestEdit, L"");
            std::wstring logPath = vielotus_win_lab::GetSpoolDir() + L"\\events.log";
            DeleteFileW(logPath.c_str());
            g_app.lastLogFileSize = 0;
            AppendLogWide(L"[LAB] Đã xoá nhật ký Trace.\r\n");
            if (g_app.hTestEdit) SetFocus(g_app.hTestEdit);
            return 0;
        }
        default:
            break;
        }
        break;
    }

    case WM_DESTROY: {
        KillTimer(hwnd, IDT_POLL_TIMER);
        StopTraceRecording();
        if (g_app.hUiFont) DeleteObject(g_app.hUiFont);
        if (g_app.hBoldFont) DeleteObject(g_app.hBoldFont);
        if (g_app.hMonoFont) DeleteObject(g_app.hMonoFont);
        PostQuitMessage(0);
        return 0;
    }
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PWSTR lpCmdLine, int nCmdShow) {
    (void)hPrevInstance;
    (void)lpCmdLine;

    HMODULE hUser32 = GetModuleHandleW(L"user32.dll");
    if (hUser32) {
        using PFN_SetProcessDpiAwarenessContext = BOOL(WINAPI *)(DPI_AWARENESS_CONTEXT);
        auto pfn = reinterpret_cast<PFN_SetProcessDpiAwarenessContext>(
            GetProcAddress(hUser32, "SetProcessDpiAwarenessContext")
        );
        if (pfn) {
            pfn(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        }
    }

    HRESULT hrCo = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    WNDCLASSEXW wcMarker{};
    wcMarker.cbSize = sizeof(wcMarker);
    wcMarker.lpfnWndProc = DefWindowProcW;
    wcMarker.hInstance = hInstance;
    wcMarker.lpszClassName = L"VieLotusLabActiveSessionWnd";
    RegisterClassExW(&wcMarker);

    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = LabWndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
    wc.lpszClassName = L"VieLotusLabWindowClass";
    RegisterClassExW(&wc);

    HDC hdc = GetDC(nullptr);
    int dpiY = GetDeviceCaps(hdc, LOGPIXELSY);
    ReleaseDC(nullptr, hdc);
    float s = (dpiY > 0) ? (static_cast<float>(dpiY) / 96.0f) : 1.0f;

    int winW = static_cast<int>(880.0f * s);
    int winH = static_cast<int>(560.0f * s);
    int scrW = GetSystemMetrics(SM_CXSCREEN);
    int scrH = GetSystemMetrics(SM_CYSCREEN);
    int posX = (scrW > winW) ? ((scrW - winW) / 2) : 40;
    int posY = (scrH > winH) ? ((scrH - winH) / 2) : 40;

#if defined(_M_ARM64) || defined(__aarch64__)
    const wchar_t *winTitle = L"Sen Việt Diagnostic Lab (VieLotusLab — Windows ARM64)";
#else
    const wchar_t *winTitle = L"Sen Việt Diagnostic Lab (VieLotusLab — Windows x64)";
#endif

    HWND hwnd = CreateWindowExW(
        0,
        L"VieLotusLabWindowClass",
        winTitle,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        posX, posY, winW, winH,
        nullptr, nullptr, hInstance, nullptr
    );
    if (!hwnd) {
        if (SUCCEEDED(hrCo)) CoUninitialize();
        return 1;
    }

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    if (SUCCEEDED(hrCo)) {
        CoUninitialize();
    }
    return static_cast<int>(msg.wParam);
}
