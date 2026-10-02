# VieLotusIM (Sen Việt)

<p align="center">
  <strong>Bộ gõ tiếng Việt Native cho macOS</strong><br>
  <em>Native Vietnamese Input Method for macOS</em>
</p>

<p align="center">
  <a href="https://www.gnu.org/licenses/gpl-3.0"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPLv3"></a>
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS%2013%2B-black.svg" alt="Platform: macOS"></a>
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%26%20Intel)-brightgreen.svg" alt="Architecture: Universal">
  <img src="https://img.shields.io/badge/Benchmark-99.51%25%20(9%2C091%20words)-brightgreen.svg" alt="Benchmark Pass Rate">
  <a href="https://stevedat.github.io/VietLotus-IM/"><img src="https://img.shields.io/badge/Website-stevedat.github.io%2FVietLotus--IM-FF5E8E.svg" alt="Website"></a>
</p>

---

## 🇻🇳 Tiếng Việt

**VieLotusIM (Sen Việt)** là bộ gõ tiếng Việt native cho macOS, tích hợp trực tiếp qua Apple `InputMethodKit`. Giải quyết triệt để 2 vấn đề lịch sử: gạch chân CJK nhấp nháy của bộ gõ mặc định và lỗi phá hỏng `Cmd + Z` của các bộ gõ dùng quyền Trợ năng (Accessibility).

### 🌸 Điểm Khác Biệt Kỹ Thuật

1. **Chuẩn Apple Native**: Chạy trực tiếp trong danh sách bàn phím hệ thống. Không dùng `CGEventTap`, không đòi quyền Trợ năng (Accessibility), bảo mật tuyệt đối.
2. **Không gạch chân CJK**: Thay thế trực tiếp ký tự tại con trỏ (`directReplacement`). Bảo toàn 100% lịch sử Undo (`Cmd + Z`) trong mọi ứng dụng.
3. **Phản hồi tức thì trong Chat**: Nhận diện phím ngay từ ký tự đầu tiên khi gõ trong Telegram, Zalo, Slack, Messenger mà không cần nhấn phím Space mồi.
4. **Nhận diện tiếng Anh thông minh (Smart Bilingual)**: Tự động khôi phục từ tiếng Anh (`wifi`, `system`, `apple`, `facebook`) khi gõ văn bản hỗn hợp.
5. **Độ trễ vi giây (Pure Swift Core)**: Xử lý âm tiết trong **10 – 25 µs**, vượt qua bài kiểm thử hồi quy 9,091 từ với tỷ lệ chính xác **99.51%**.
6. **Zero-Logging**: Hoạt động offline 100%, không ghi bất kỳ dữ liệu phím gõ nào ra đĩa.

### 🏛️ Kiến Trúc Hệ Thống

```text
┌──────────────────────────────────────────────────────────────┐
│  LỚP ĐIỀU KHIỂN: Swift Native (macOS)                        │
│  • Tích hợp trực tiếp vào bàn phím hệ thống của Apple        │
│  • Bắt và điều phối sự kiện phím gõ không độ trễ             │
│  • Giao tiếp tức thì với các ứng dụng soạn thảo              │
└──────────────────────────────┬───────────────────────────────┘
                               │ (Gọi trực tiếp Pure Swift)
┌──────────────────────────────┴───────────────────────────────┐
│  LÕI XỬ LÝ TIẾNG VIỆT: Pure Swift Engine (VieLotusCore)      │
│  • Xử lý kiểu gõ Telex và VNI tốc độ cao                     │
│  • Bỏ dấu chuẩn mới (hoà/hòa), viết tắt vần cuối             │
│  • Bộ đệm vòng 32 từ hỗ trợ lùi con trỏ sửa từ               │
│  • Tự động nhận diện từ tiếng Anh (Smart Bilingual)          │
└──────────────────────────────────────────────────────────────┘
```

### 🗺️ Lộ Trình (Roadmap)

- [x] **macOS v1.0.0**: Bản phát hành chính thức (Universal Binary cho Apple Silicon & Intel).
- [x] **macOS v1.1.0 & VieLotusLab**: Nâng tỷ lệ kiểm thử lên 99.51% với ràng buộc ngữ âm Pure Swift; ra mắt VieLotusLab chẩn đoán nhịp gõ và xuất gói báo cáo lỗi khép kín.
- [ ] **Mở rộng iOS & iPadOS**: Bàn phím mở rộng cho iPhone/iPad dùng chung lõi `VieLotusCore`.
- [ ] **Đồng bộ bảng gõ tắt**: Tùy biến viết tắt và từ điển cá nhân hóa.

### 🚀 Cài Đặt Nhanh

1. Tải **`VieLotusIM.pkg`** (hoặc `.dmg`) từ [Releases](https://github.com/stevedat/VietLotus-IM/releases).
2. Chạy gói cài đặt `.pkg` (Gói cài đặt đã được ký số chính thức Apple Developer ID).
3. 🔄 **Lưu ý quan trọng (Đăng xuất):** Sau khi cài đặt xong, vui lòng **Đăng xuất (Log Out)** và đăng nhập lại một lần để macOS làm mới danh sách bộ gõ.
4. Mở **System Settings** $\rightarrow$ **Keyboard** $\rightarrow$ **Text Input** (Nguồn nhập) bấm **Edit...** $\rightarrow$ bấm **`+`** chọn **Vietnamese** $\rightarrow$ thêm **VieLotusIM** (hoặc Sen Việt).


Dành cho Tester tham gia thử nghiệm và chẩn đoán nhịp gõ:
- Tải thêm **`VieLotusLab.dmg`** từ trang Releases để theo dõi ứng dụng ngoài và xuất gói báo cáo lỗi.
- Xem chi tiết quy trình kiểm thử khép kín tại [docs/LAB_TESTING_GUIDE.md](docs/LAB_TESTING_GUIDE.md).

Tự biên dịch từ mã nguồn:
```bash
git clone https://github.com/stevedat/VietLotus-IM.git
cd VietLotus-IM
./scripts/build_pkg.sh 1.1.0
```

---

## 🇬🇧 English

**VieLotusIM (Sen Việt)** is a native macOS Vietnamese input method built on Apple's `InputMethodKit`. It eliminates both macOS CJK underline flicker and legacy third-party Undo (`Cmd + Z`) breakage.

### 🌸 Technical Highlights

1. **Pure Apple Native**: Operates as a native system keyboard. Zero accessibility permissions, zero low-level event taps (`CGEventTap`).
2. **Zero-Flicker & Preserved Undo**: Direct text replacement at the caret position. Eliminates CJK underline flicker while preserving `Cmd + Z` history.
3. **Instant Chat Response**: Immediate character composition in Telegram, Zalo, Slack, and Discord without requiring a priming Space key.
4. **Smart Bilingual Detection**: Automatically preserves standard English words (`wifi`, `system`, `apple`, `database`) during mixed typing.
5. **Microsecond Latency (Pure Swift Core)**: Syllable transforms in **10 – 25 µs** with a verified **99.51% pass rate** on a 9,091-word benchmark.
6. **Zero-Logging Privacy**: Fully offline, zero disk logging, zero telemetry.

### 🏛️ System Architecture

```text
┌──────────────────────────────────────────────────────────────┐
│  SYSTEM CONTROLLER: Swift Native (macOS)                     │
│  • Integrates directly into native Apple keyboard sources    │
│  • Dispatches keystroke events without event-tap overhead    │
│  • Direct text replacement across all macOS applications     │
└──────────────────────────────┬───────────────────────────────┘
                               │ (Direct Swift Call)
┌──────────────────────────────┴───────────────────────────────┐
│  VIETNAMESE ENGINE: Pure Swift Core (VieLotusCore)           │
│  • High-performance Telex & VNI syllable transformation      │
│  • Modern tone placement & relaxed coda consonants           │
│  • 32-word ring buffer for caret step-back editing           │
│  • Automatic English word detection (Smart Bilingual)        │
└──────────────────────────────────────────────────────────────┘
```

### 🗺️ Roadmap

- [x] **macOS v1.0.0**: Universal release for Apple Silicon and Intel.
- [x] **macOS v1.1.0 & VieLotusLab**: Elevated benchmark pass rate to 99.51% via pure Swift phonological rules; introduced VieLotusLab typing diagnostics app and closed-loop issue export.
- [ ] **iOS & iPadOS Expansion**: Keyboard extension for iPhone/iPad sharing `VieLotusCore`.
- [ ] **Custom Shorthands**: User-configurable abbreviations and custom vocabulary.

### 🚀 Quick Install

1. Download **`VieLotusIM.pkg`** (or `.dmg`) from [Releases](https://github.com/stevedat/VietLotus-IM/releases).
2. Run the `.pkg` installer (Signed with official Apple Developer ID).
3. 🔄 **Important Note (Log Out):** After installing, please **Log Out** and log back in once for macOS to refresh the Input Sources list.
4. Open **System Settings** $\rightarrow$ **Keyboard** $\rightarrow$ **Text Input** click **Edit...** $\rightarrow$ click **`+`** select **Vietnamese** $\rightarrow$ add **VieLotusIM** (or Sen Việt).

Build from source:
```bash
git clone https://github.com/stevedat/VietLotus-IM.git
cd VietLotus-IM
./scripts/build_pkg.sh 1.1.0
```

---

## 📄 License & Ecosystem

* **License**: [GNU General Public License v3.0](LICENSE).
* **Ecosystem**: [YouPersona.com](https://youpersona.com).
* **Documentation**: [Compatibility](docs/COMPATIBILITY.md) · [Changelog](docs/CHANGELOG.md) · [Branding](docs/BRANDING.md) · [Third-Party Notices](docs/THIRD_PARTY_NOTICES.md).
* **Community**: [Contributing](.github/CONTRIBUTING.md) · [Security](.github/SECURITY.md) · [Code of Conduct](.github/CODE_OF_CONDUCT.md).

---

*Created by **Steve Dat** ([@stevedat](https://github.com/stevedat)). Engineered and Copyrighted by **Nido Holdings**.*
