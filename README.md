# VieLotusIM (Sen Việt)

<p align="center">
  <strong>Bộ gõ tiếng Việt Native cho macOS</strong><br>
  <em>Native Vietnamese Input Method for macOS</em>
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS%2013%2B-black.svg" alt="Platform: macOS"></a>
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%26%20Intel)-brightgreen.svg" alt="Architecture: Universal">
  <img src="https://img.shields.io/badge/Benchmark-99.99%25%20(9%2C091%20words)-brightgreen.svg" alt="Benchmark Pass Rate">
  <a href="https://stevedat.github.io/VieLotus-IM/"><img src="https://img.shields.io/badge/Website-stevedat.github.io%2FVieLotus--IM-FF5E8E.svg" alt="Website"></a>
</p>

---

## 🇻🇳 Tiếng Việt

**VieLotusIM (Sen Việt)** khởi nguồn từ những trăn trở rất quen thuộc của người dùng macOS: chúng ta thường phải chấp nhận sống chung với những bất tiện nhỏ hàng ngày — từ việc lệnh Hoàn tác (`Cmd + Z`) thỉnh thoảng hoạt động không như ý trong các công cụ lập trình hay thiết kế, cho đến cảm giác đắn đo khi phải cấp quyền Trợ năng (Accessibility) và can thiệp sự kiện tầng thấp (`CGEventTap`) cho một công cụ gõ chữ.

Sen Việt là một thử nghiệm mã nguồn mở nhằm tìm kiếm hướng tiếp cận tự nhiên hơn: quay về với framework chuẩn của Apple (`InputMethodKit`) bằng ngôn ngữ Swift thuần túy. Hoạt động như một nguồn nhập liệu tiêu chuẩn của hệ điều hành, bộ gõ vận hành an toàn mà không cần đến sự hiện diện của `CGEventTap` hay đòi hỏi các quyền can thiệp đặc biệt.

Thực tế, hệ sinh thái phần mềm trên macOS vô cùng phong phú — từ các ứng dụng AppKit truyền thống, trình duyệt web, các ứng dụng Electron cho đến các terminal hiện đại. Không một giải pháp đơn lẻ nào có thể hoàn thiện ngay từ đầu trên mọi ô nhập liệu. Đó là lý do dự án phát triển kèm **VieLotusLab** — một không gian đồng hành để người dùng và cộng đồng cùng theo dõi hành vi gõ thực tế, phát hiện các tình huống góc và cùng nhau đóng góp để bộ gõ ngày càng hoàn thiện hơn.

### 🌸 Điểm Nhấn Kiến Trúc

1. **Chuẩn Apple Native**: Tích hợp trực tiếp qua `InputMethodKit`, vận hành an toàn như một nguồn nhập liệu tiêu chuẩn của macOS.
2. **Không đòi hỏi quyền can thiệp**: Hoạt động bình thường mà không cần cấp quyền Trợ năng (Accessibility) hay dùng `CGEventTap`.
3. **Bộ điều phối hiển thị thông minh (Adaptive Presentation Engine)**:
   - **Direct Replacement**: Thay thế trực tiếp không gạch chân trên các ứng dụng AppKit gốc (Pages, TextEdit, Safari, Xcode, Spotlight) và tối ưu dòng lệnh (Terminal Direct).
   - **Marked Text chuẩn W3C**: Cơ chế gạch chân soạn thảo chuẩn mực của macOS trên các ứng dụng nền Web / Electron (Chrome, VS Code, Slack, Discord, Notion...). Nhờ đó, **triệt tiêu hoàn toàn lỗi nuốt chữ, lặp chữ (`t-ti-tiế-tiếng`) và nhảy con trỏ** do Virtual DOM diffing. Khi kết thúc từ, văn bản chuyển thành chữ thường sạch sẽ ngay lập tức.
   - Bảo toàn trọn vẹn lịch sử hoàn tác (`Cmd + Z`) trên toàn bộ ứng dụng.
4. **Hỗ trợ gõ song ngữ (Smart Bilingual)**: Nhận diện và giữ nguyên các từ tiếng Anh thông dụng, giảm bớt thao tác phải bật/tắt bộ gõ khi viết tài liệu kỹ thuật.
5. **Không gian thử nghiệm mở (VieLotusLab)**: Đi kèm ứng dụng Lab giúp cộng đồng cùng kiểm thử nhịp gõ trên từng ứng dụng ngoài và xuất gói chẩn đoán lỗi có cấu trúc.
6. **Tôn trọng quyền riêng tư**: Hoạt động hoàn toàn offline, không ghi lại phím gõ ra đĩa và không gửi dữ liệu mạng.

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
- [x] **macOS v1.1.0 & VieLotusLab**: Giới thiệu công cụ VieLotusLab chẩn đoán nhịp gõ và xuất gói báo cáo lỗi khép kín.
- [x] **macOS v1.1.1 (Mới nhất)**: Chuyển giấy phép sang **MIT License**; sửa triệt để lỗi xóa lùi dở từ (Partial Backspace Retention); hoàn thiện bộ điều phối hiển thị thông minh (Adaptive Presentation Engine); nâng tỷ lệ kiểm thử lên **99.99%** (9,090 / 9,091 từ).
- [ ] **Mở rộng iOS & iPadOS**: Bàn phím mở rộng cho iPhone/iPad dùng chung lõi `VieLotusCore`.
- [ ] **Đồng bộ bảng gõ tắt**: Tùy biến viết tắt và từ điển cá nhân hóa.

### 🚀 Cài Đặt Nhanh

1. Tải **`VieLotusIM.pkg`** (hoặc `.dmg`) từ [Releases v1.1.1](https://github.com/stevedat/VieLotus-IM/releases/tag/v1.1.1).
2. Chạy gói cài đặt `.pkg` (Gói cài đặt đã được ký số chính thức Apple Developer ID).
3. 🔄 **Lưu ý quan trọng (Đăng xuất):** Sau khi cài đặt xong, vui lòng **Đăng xuất (Log Out)** và đăng nhập lại một lần để macOS làm mới danh sách bộ gõ.
4. Mở **System Settings** $\rightarrow$ **Keyboard** $\rightarrow$ **Text Input** (Nguồn nhập) bấm **Edit...** $\rightarrow$ bấm **`+`** chọn **Vietnamese** $\rightarrow$ thêm **VieLotusIM** (hoặc Sen Việt).


Dành cho Tester tham gia thử nghiệm và chẩn đoán nhịp gõ:
- Tải thêm **`VieLotusLab.dmg`** từ [Releases v1.1.1](https://github.com/stevedat/VieLotus-IM/releases/tag/v1.1.1) để theo dõi ứng dụng ngoài và xuất gói báo cáo lỗi.
- Xem chi tiết quy trình kiểm thử khép kín tại [docs/LAB_TESTING_GUIDE.md](docs/LAB_TESTING_GUIDE.md).
- Tham gia thảo luận và đóng góp ý kiến cộng đồng tại [GitHub Discussions](https://github.com/stevedat/VieLotus-IM/discussions).

Tự biên dịch từ mã nguồn:
```bash
git clone https://github.com/stevedat/VieLotus-IM.git
cd VieLotus-IM
./scripts/build_pkg.sh 1.1.1
```

---

## 🇬🇧 English

**VieLotusIM (Sen Việt)** began from a very familiar experience on macOS: for years, many of us simply adapted to subtle daily frictions — unexpected Undo (`Cmd + Z`) behavior in editors and design tools, or the hesitation of granting system-wide Accessibility permissions and low-level event taps (`CGEventTap`) just to type in our language.

Sen Việt is an open-source exploration of a cleaner alternative: returning to Apple’s native `InputMethodKit` framework written in pure Swift. By living directly inside the operating system's standard text input pipeline, it operates without requiring `CGEventTap` or elevated system privileges.

In practice, the macOS software landscape is vast — spanning AppKit utilities, web browsers, Electron suites, and terminal emulators. No single approach handles every bespoke text control seamlessly out of the box. That is why the project includes **VieLotusLab** — an open diagnostics companion where developers and community members can observe real-world keystroke interactions, capture tricky edge cases with privacy masking, and collaborate on making the typing experience smoother for everyone.

### 🌸 Architectural Highlights

1. **Native Input Architecture**: Integrated directly via `InputMethodKit`, behaving as a standard macOS system input source.
2. **Zero Elevated Privileges**: Runs safely in user space without Accessibility permissions or `CGEventTap` event interception.
3. **Adaptive Presentation Engine**:
   - **Direct Replacement**: Instant, zero-flicker replacement without marked text underlines on native AppKit applications (Pages, TextEdit, Safari, Xcode, Spotlight) and command-line environments (Terminal Direct).
   - **W3C Standard Marked Text**: Apple's native marked text composition for Web and Electron applications (Chrome, VS Code, Slack, Discord, Notion...). This **completely eliminates duplicate keystrokes (`t-ti-tiế-tiếng`), dropped characters, and erratic caret jumping** caused by asynchronous Virtual DOM diffing. Once the word is finished, clean plain text is committed immediately.
   - Fully preserves the native `Cmd + Z` undo history across all applications.
4. **Bilingual Typing Support**: Heuristic detection preserves common English terms during mixed typing, minimizing manual keyboard switching.
5. **Community Diagnostics (VieLotusLab)**: A dedicated companion app to inspect typing flows across diverse applications and export structured diagnostic packets.
6. **Privacy by Design**: Fully offline, zero keystroke disk logging, zero telemetry.

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
- [x] **macOS v1.1.0 & VieLotusLab**: Introduced VieLotusLab typing diagnostics app and closed-loop issue export.
- [x] **macOS v1.1.1 (Latest)**: Transitioned to **MIT License**; fixed partial backspace prefix retention; Adaptive Presentation Engine (Direct Replacement vs W3C Marked Text); elevated benchmark accuracy to **99.99%** (9,090 / 9,091 words).
- [ ] **iOS & iPadOS Expansion**: Keyboard extension for iPhone/iPad sharing `VieLotusCore`.
- [ ] **Custom Shorthands**: User-configurable abbreviations and custom vocabulary.

### 🚀 Quick Install

1. Download **`VieLotusIM.pkg`** (or `.dmg`) from [Releases v1.1.1](https://github.com/stevedat/VieLotus-IM/releases/tag/v1.1.1).
2. Run the `.pkg` installer (Signed with official Apple Developer ID).
3. 🔄 **Important Note (Log Out):** After installing, please **Log Out** and log back in once for macOS to refresh the Input Sources list.
4. Open **System Settings** $\rightarrow$ **Keyboard** $\rightarrow$ **Text Input** click **Edit...** $\rightarrow$ click **`+`** select **Vietnamese** $\rightarrow$ add **VieLotusIM** (or Sen Việt).

Build from source:
```bash
git clone https://github.com/stevedat/VieLotus-IM.git
cd VieLotus-IM
./scripts/build_pkg.sh 1.1.1
```

---

## 📄 License & Ecosystem

* **License**: [MIT License](LICENSE).
* **Ecosystem**: [YouPersona.com](https://youpersona.com).
* **Documentation**: [Compatibility](docs/COMPATIBILITY.md) · [Changelog](docs/CHANGELOG.md) · [Branding](docs/BRANDING.md) · [Third-Party Notices](docs/THIRD_PARTY_NOTICES.md).
* **Discussions**: [GitHub Discussions](https://github.com/stevedat/VieLotus-IM/discussions).
* **Community**: [Contributing](.github/CONTRIBUTING.md) · [Security](.github/SECURITY.md) · [Code of Conduct](.github/CODE_OF_CONDUCT.md).

---

*Created by **Steve Dat** ([@stevedat](https://github.com/stevedat)). Engineered and Copyrighted by **Nido Holdings**.*
