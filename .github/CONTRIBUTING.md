# Đóng góp phát triển Sen Việt / Contributing to VietLotusIM

Cảm ơn bạn đã quan tâm đến việc đóng góp cho dự án Sen Việt (VieLotusIM)! / Thank you for your interest in contributing to VietLotusIM!

---

## 🇻🇳 Hướng Dẫn Dành Cho Lập Trình Viên

### 1. Triết Lý Phát Triển
- **Native & Performance First:** Sử dụng thuần túy Apple `InputMethodKit`, không dùng `CGEventTap` hay Accessibility API xâm lấn.
- **Zero-Logging Posture:** Tuyệt đối không lưu vết phím gõ của người dùng ra ổ cứng (`os.Logger` chỉ dùng trong `#if DEBUG`).
- **Benchmark Quality Gate:** Mọi thay đổi thuật toán xử lý âm tiết phải vượt qua bài kiểm thử hồi quy 9.091 từ (`>= 98.0%`).

### 2. Thiết Lập Môi Trường
- **Yêu cầu:** macOS 13.0 trở lên, Xcode 15+ / Command Line Tools, Swift 5.10+.
- **Biên dịch dự án:**
  ```bash
  swift build
  ```
- **Chạy kiểm thử đơn vị:**
  ```bash
  swift test
  ```
- **Chạy bộ đo kiểm chuẩn (Benchmark Regression Suite):**
  ```bash
  swift run VieLotusCLI --benchmark --threshold 98.0
  ```
- **Đóng gói bộ cài đặt Universal PKG:**
  ```bash
  ./scripts/build_pkg.sh 1.0.0
  ```

### 3. Quy Trình Gửi Pull Request (PR)
1. Fork repository và tạo nhánh tính năng mới (`feature/ten-tinh-nang` hoặc `fix/ten-loi`).
2. Đảm bảo toàn bộ unit test và benchmark quality gate đều vượt qua.
3. Kiểm tra định dạng mã nguồn không có khoảng trắng thừa:
   ```bash
   git diff --check
   ```
4. Gửi Pull Request với mô tả rõ ràng về thay đổi và ca kiểm thử thực tế.

---

## 🇬🇧 Developer Guide & Pull Request Workflow

### 1. Core Principles
- **Native & Privacy-First:** Pure Apple `InputMethodKit` integration. No invasive key event taps or accessibility permissions. Zero keystroke logging.
- **Regression Guard:** Any syllable transformation logic must pass the official 9,091-word regression suite at `>= 98.0%`.

### 2. Local Setup & Testing
```bash
swift build                             # Build all targets
swift test                              # Run unit tests
swift run VieLotusCLI --benchmark       # Run 9,091-word regression suite
./scripts/build_pkg.sh 1.0.0            # Build universal PKG installer
```

### 3. Submitting PRs
- Ensure `swift test` and `swift run VieLotusCLI --benchmark --threshold 98.0` pass with 0 failures.
- Verify zero trailing whitespace errors with `git diff --check`.
- All contributions are licensed under the [Apache License 2.0](LICENSE).
