# Chính sách Quyền riêng tư / Privacy Policy — Sen Việt (VieLotus IM)

**Cập nhật lần cuối / Last Updated:** 26/10/2026  
**Nhà phát triển / Developer:** Trần Phát Đạt (Steve Dat)  
**Trang chủ / Homepage:** [https://github.com/stevedat/VieLotus-IM](https://github.com/stevedat/VieLotus-IM)  
**Liên hệ / Contact:** [https://github.com/stevedat/VieLotus-IM/issues](https://github.com/stevedat/VieLotus-IM/issues)

---

## 🇻🇳 Tiếng Việt (Vietnamese)

### 1. Cam kết cốt lõi: 100% Xử lý Cục bộ & Không thu thập dữ liệu (Zero Keylogging)

**Sen Việt (VieLotus IM)** là bộ gõ tiếng Việt đa nền tảng (macOS, Windows, iOS/iPadOS, Android, Linux) được thiết kế với nguyên tắc **Quyền riêng tư Tuyệt đối (Privacy by Design)**:

- **Không thu thập thao tác phím (Zero Keylogging):** Toàn bộ quá trình phân tích âm tiết tiếng Việt, chuyển đổi dấu câu (Telex / VNI), khôi phục từ song ngữ Anh–Việt (Smart Bilingual) và gõ tắt (Macro) đều diễn ra **100% trực tiếp trong bộ nhớ RAM trên thiết bị của bạn**.
- **Không kết nối máy chủ từ xa (100% Offline):** Bộ gõ **không** gửi bất kỳ văn bản, từ vựng, mật khẩu, thông tin cá nhân hay nhật ký sử dụng (telemetry/analytics) nào ra ngoài Internet.
- **Không ghi nhật ký đĩa (Zero Disk Keystroke Logging):** Nhân bộ gõ không bao giờ ghi lịch sử phím bấm của người dùng xuống ổ cứng.

### 2. Dữ liệu được lưu trữ cục bộ trên thiết bị

Sen Việt chỉ lưu trữ các cấu hình tùy chỉnh do chính bạn thiết lập ngay trên thiết bị của bạn:
- **Cấu hình bộ gõ:** Kiểu gõ (Telex / VNI), chế độ song ngữ thông minh, quy tắc đặt dấu và phím tắt chuyển chế độ.
  - Trên **Windows**: Lưu trong Registry cục bộ của người dùng (`HKEY_CURRENT_USER\Software\VieLotus`).
  - Trên **macOS / iOS / iPadOS**: Lưu trong `UserDefaults` cục bộ của ứng dụng.
  - Trên **Android**: Lưu trong `SharedPreferences` cục bộ của ứng dụng.
  - Trên **Linux**: Lưu trong thư mục cấu hình cá nhân (`~/.config/vielotus/`).
- **Bảng gõ tắt (Macros) & Từ điển cá nhân:** Chỉ lưu cục bộ trên máy của bạn và không bao giờ tự động tải lên đám mây.

### 3. Quyền hệ thống (System Permissions)

- **Windows (Text Services Framework — TSF):** Tệp `VieLotusTIP.dll` hoạt động như một dịch vụ nhập liệu chuẩn của Windows (TSF Input Method Editor) để chuyển đổi ký tự tiếng Việt trong ứng dụng bạn đang gõ. Phần mềm không cài đặt trình theo dõi bàn phím tầng thấp (`WH_KEYBOARD_LL`) và không truy cập mạng.
- **macOS (InputMethodKit):** Sử dụng giao thức chuẩn `IMKInputController` của Apple, không yêu cầu quyền Trợ năng (Accessibility / `CGEventTap`).
- **iOS / iPadOS & Android:** Chỉ sử dụng API bàn phím tiêu chuẩn của hệ điều hành (`UIInputViewController` / `InputMethodService`).

### 4. Chia sẻ dữ liệu với bên thứ ba

Vì Sen Việt **không thu thập bất kỳ dữ liệu nào của người dùng**, chúng tôi **không có dữ liệu** để bán, trao đổi hoặc chia sẻ với bất kỳ bên thứ ba, mạng quảng cáo hay tổ chức phân tích nào.

---

## 🌐 English

### 1. Core Commitment: 100% On-Device Processing & Zero Data Collection

**Sen Việt (VieLotus IM)** is a cross-platform Vietnamese Input Method Editor (available on macOS, Windows, iOS/iPadOS, Android, and Linux) architected strictly around **Privacy by Design**:

- **Zero Keylogging:** All Vietnamese syllable composition (Telex / VNI), Smart Bilingual English–Vietnamese restoration, and text expansion (Macros) are processed **100% locally in volatile memory (RAM) on your device**.
- **100% Offline Operation:** VieLotus IM does **not** transmit any keystrokes, typed text, passwords, personal data, crash reports, or telemetry/analytics over the network.
- **Zero Disk Keystroke Logging:** The input method engine never writes user keystrokes or typed content to disk storage.

### 2. Locally Stored Preferences

VieLotus IM stores only your user-configured settings locally on your device:
- **Input Method Preferences:** Input mode (Telex / VNI), Smart Bilingual toggle, tone placement preferences, and toggle hotkeys.
  - **Windows**: Stored in the current user's local registry hive (`HKEY_CURRENT_USER\Software\VieLotus`).
  - **macOS / iOS / iPadOS**: Stored in local `UserDefaults`.
  - **Android**: Stored in local `SharedPreferences`.
  - **Linux**: Stored in `~/.config/vielotus/`.
- **Custom Macros & User Dictionary:** Stored exclusively on your local device and never uploaded to any external server.

### 3. Platform Permissions & Input Method Architecture

- **Windows (Text Services Framework — TSF):** `VieLotusTIP.dll` operates strictly through Microsoft's standard Text Services Framework (`ITfTextInputProcessorEx`) to compose Vietnamese characters in the active text field. It uses no low-level keyboard hooks (`WH_KEYBOARD_LL`) and makes no network connections.
- **macOS (InputMethodKit):** Built exclusively on Apple's standard `IMKInputController` API without requiring Accessibility (`CGEventTap`) permissions.
- **iOS / iPadOS & Android:** Built on standard OS keyboard extension APIs (`UIInputViewController` / `InputMethodService`) with no network transmission.

### 4. Third-Party Data Sharing

Because VieLotus IM **collects zero personal data or typing data**, no user data is ever sold, shared, or disclosed to any third party, advertiser, or analytics provider.

### 5. Contact Us

If you have any questions regarding this Privacy Policy or our source code, please open an issue on our official repository at [https://github.com/stevedat/VieLotus-IM/issues](https://github.com/stevedat/VieLotus-IM/issues).
