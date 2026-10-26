# fcitx5-vielotus (Sen Việt for Linux & Windows)

Plugin tích hợp bộ gõ tiếng Việt thế hệ mới **VieLotus (Sen Việt)** vào hệ thống **Fcitx5**, hỗ trợ cả **Linux (Wayland & X11)** và **Windows (thông qua `fcitx5-windows` / TSF)**.

---

## 1. Kiến Trúc (Architecture)

```
[ Bàn Phím Người Dùng ]
         │
         ▼
[ Fcitx5 (Wayland/X11 trên Linux hoặc TSF trên Windows) ]
         │
         ▼
[ fcitx5-vielotus (C++ Engine Plugin) ]
         │
         ▼ (C-ABI vielotus.h)
[ libVieLotusCAPI (Swift 6 Core Engine) ]
```

* **Core Engine**: Sử dụng 100% chung thuật toán với bản macOS, bảo toàn **99.97%** độ chính xác trên 9.091 test cases.
* **Non-invasive**: Sử dụng chuẩn `Preedit` và `CommitString` của Fcitx5, không giả lập phím ảo Backspace, không nháy chữ trong trình duyệt hay terminal.

---

## 2. Hướng Dẫn Biên Dịch trên Linux (Ubuntu / Debian / Fedora / Arch)

### Bước 1: Cài đặt công cụ và thư viện Fcitx5
* **Ubuntu / Debian**:
  ```bash
  sudo apt install -y cmake extra-cmake-modules fcitx5 fcitx5-modules-dev libfcitx5core-dev libfcitx5utils-dev
  ```
* **Arch Linux**:
  ```bash
  sudo pacman -S --needed cmake extra-cmake-modules fcitx5 fcitx5-devel
  ```

### Bước 2: Biên dịch thư viện lõi `libVieLotusCAPI`
Từ thư mục gốc của repository:
```bash
swift build -c release --product VieLotusCAPI
```
Thư viện `.so` sẽ được tạo tại `.build/release/libVieLotusCAPI.so`.

### Bước 3: Biên dịch và cài đặt Fcitx5 plugin
```bash
cd CrossPlatform/fcitx5-vielotus
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make -j$(nproc)
sudo make install
```

### Bước 4: Khởi động lại Fcitx5 và kích hoạt
```bash
fcitx5 -r -d
```
Mở `fcitx5-configtool`, thêm **Sen Việt (Telex)** hoặc **Sen Việt (VNI)** vào danh sách bộ gõ.

---

## 3. Hướng Dẫn Biên Dịch trên Windows (`fcitx5-windows`)

1. Cài đặt môi trường `MSYS2` / `MinGW-w64` hoặc `MSVC Clang`.
2. Biên dịch lõi `VieLotusCAPI` trên Windows bằng Swift 6:
   ```cmd
   swift build -c release --product VieLotusCAPI
   ```
   Tạo ra `VieLotusCAPI.dll`.
3. Biên dịch addon Fcitx5 với `fcitx5-windows` SDK:
   ```cmd
   cmake -B build -G "Ninja" -DCMAKE_PREFIX_PATH="C:/path/to/fcitx5-windows-sdk"
   cmake --build build --config Release
   ```
4. Copy `vielotus.dll` và `VieLotusCAPI.dll` vào thư mục `fcitx5/lib/fcitx5/` của Fcitx5-Windows.
