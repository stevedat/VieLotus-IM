# VieLotusTIP — Native Windows Text Services Framework (TSF) Input Processor
## Bộ Gõ Tiếng Việt Thế Hệ Mới Chuẩn Microsoft TSF (In-Process COM)

---

## 1. Giới Thiệu & Triết Lý Thiết Kế

Khác biệt hoàn toàn với các bộ gõ truyền thống trên Windows như UniKey, EVKey, hay OpenKey (vốn sử dụng `SetWindowsHookEx` và gửi phím ảo `SendInput` dễ bị vỡ nhịp, bị Antivirus nghi ngờ, và bị Anti-Cheat chặn trong game), **VieLotusTIP** là một **Text Input Processor (TIP)** chuẩn mực của hệ điều hành Windows:

- **100% Native Text Services Framework (TSF)**: Tương tự như IME mặc định của Microsoft (Japanese IME, Chinese IME, Korean IME).
- **In-Process COM DLL**: Được Windows nạp trực tiếp vào process đang có focus bàn phím (Notepad, Word, Excel, Chrome, VS Code, Windows Terminal...).
- **Đăng ký chuẩn mực ngôn ngữ**:
  - Mã ngôn ngữ: `vi-VN (0x042A)`
  - Bàn phím thay thế: `US Keyboard (0x04090409)`
  - CLSID: `{C7B08E9D-4762-4C97-8B1F-522197A598DC}`
- **Không gạch chân (Zero-Underline Direct Typing)**:
  - Khi gõ, ký tự xuất hiện trực tiếp trong ứng dụng.
  - Khi có biến âm tiếng Việt (như `w`, `s`, `f`...): TSF gọi `ITfEditSession` để thực hiện giao dịch chỉnh sửa văn bản nguyên tử (atomic edit transaction), xóa số ký tự trước con trỏ và chèn chữ đã bỏ dấu chuẩn xác.
  - Con trỏ luôn ở cuối chữ, không bao giờ nhảy lộn xộn hay nhân đôi ký tự.

---

## 2. Cấu Trúc Mã Nguồn

```
CrossPlatform/windows-tsf/
├── CMakeLists.txt              # CMake build script (MSVC / MinGW-w64)
├── VieLotusTIP.def             # Xuất các hàm COM chuẩn (DllGetClassObject, DllRegisterServer...)
├── src/
│   ├── Globals.h / .cpp        # GUIDs, hInst, reference counting
│   ├── ClassFactory.h / .cpp   # IClassFactory tạo VieLotusTIP instance
│   ├── VieLotusTIP.h / .cpp    # ITfTextInputProcessorEx, ITfKeyEventSink, ITfThreadMgrEventSink
│   ├── EditSession.h / .cpp    # ITfEditSession thực thi thay đổi text trong Document Lock
│   ├── Register.h / .cpp       # Đăng ký COM CLSID và TSF Language Profile vào Windows Registry
│   └── dllmain.cpp             # DllMain & COM exported entry points
└── README.md
```

---

## 3. Quy Trình Đăng Ký & Gỡ Cài Đặt

### Đăng ký thủ công (Command Prompt chạy quyền Administrator):
```cmd
regsvr32 /s VieLotusTIP.dll
```
Ngay sau lệnh này, Windows sẽ nhận diện `Tiếng Việt (Sen Việt - Telex)` trong danh sách ngôn ngữ bàn phím (`Windows + Space`).

### Gỡ cài đặt thủ công:
```cmd
regsvr32 /u /s VieLotusTIP.dll
```

### Đóng gói tự động:
File kịch bản Inno Setup tại `scripts/windows/VieLotus-Setup.iss` sẽ tự động tạo file cài đặt `VieLotus-Setup-x64.exe` một cú click chuột: tự động đăng ký DLL COM vào hệ thống và kích hoạt ngay tức thì.
