# Nhật ký Thay đổi (Changelog)

Tất cả thay đổi đáng chú ý của dự án **Sen Việt (VieLotusIM)** sẽ được ghi chép tại tệp này theo định dạng chuẩn [Keep a Changelog](https://keepachangelog.com/vi/1.0.0/). Dự án tuân thủ [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-10-02

### Tính năng mới & Cải tiến (Added & Improved)
- **Lõi Pure Swift & Ràng buộc Ngữ âm học (Phonological Constraints)**:
  - Tích hợp luật âm cuối tắc (`-c, -ch, -p, -t` bắt buộc phải mang thanh Sắc hoặc Nặng), loại bỏ triệt để các trường hợp gõ lỗi từ tiếng Anh thành âm tiết rác như `mêt`, `sỏt`, `heảt`, `pỏt`, `chủch`.
  - Bổ sung bộ lọc nguyên âm đôi / nguyên âm ba không tồn tại trong tiếng Việt (`ae`, `ea`, `io`...).
  - Mở rộng bộ đệm từ điển tiếng Anh lên 65,536 mục, giải quyết nghẽn IPC `NSSpellServer` và tối ưu hóa thời gian phản hồi.
  - Nâng tỷ lệ chính xác bộ kiểm thử hồi quy 9,091 từ từ 98.30% lên **99.51%** (9,046 / 9,091 từ), trong đó tỷ lệ khôi phục từ tiếng Anh (`restore_raw`) đạt **99.42%** (7,174 / 7,216).
- **Bộ công cụ chẩn đoán VieLotusLab (Mới)**:
  - Phát hành ứng dụng độc lập **VieLotusLab** (`VieLotusLab.dmg`) hỗ trợ quan sát nhịp gõ phím và sự kiện `AXUIElement` trên các ứng dụng ngoài.
  - Bảo vệ quyền riêng tư nghiêm ngặt: Tự động che mờ (masking) nội dung tài liệu có sẵn, chỉ ghi lại chuỗi phím do tester chủ động nhập trong phiên thử nghiệm.
  - Luồng xuất báo cáo lỗi khép kín (JSON & Markdown) đính kèm đầy đủ thông tin môi trường, phiên bản OS, bundle ID và timeline sự kiện.
- **Quy trình Phát hành & Công chứng Apple Tự động**:
  - Tích hợp Apple Notarization chính thức với Developer ID qua GitHub Actions CI/CD.
  - Script kiểm tra tính toàn vẹn 5 asset phát hành (`verify_release_assets.sh`) đảm bảo khớp mã băm SHA-256 trên cả môi trường cục bộ và GitHub Release.

### Sửa lỗi (Fixed)
- Sửa hàng loạt từ tiếng Anh phổ biến từng bị nhận diện nhầm khi gõ Telex: `more`, `your`, `are`, `we`, `bios`, `yarn`, `aes`, `await`, `ios`, `nginx`, `nostr`, `sizeof`, `uefi`, `where`, `there`, `their`, `share`, `before`, `sure`, `were`, `care`, `core`, `search`, `our`, `use`, `year`, `years`, `next`, `music`, `post`, `very`, `does`, `research`, `life`, `way`.

---

## [1.0.0] - 2026-09-30

### Tính năng mới (Added)
- **Kiến trúc Native InputMethodKit**: Tích hợp trực tiếp với macOS Text Input Management qua `IMKInputController` và `NSTextInputClient`.
- **Lõi xử lý tiếng Việt tốc độ cao**: Lõi Pure Swift thuần túy (`VieLotusCore`), độ trễ xử lý phím từ 10 - 25 µs.
- **Hỗ trợ 2 kiểu gõ phổ biến**: Telex và VNI.
- **Tự động khôi phục từ tiếng Anh (Smart Bilingual)**: Nhận diện hình vị và ngữ cảnh không gian làm việc để khôi phục từ tiếng Anh bị biến dạng mà không cần nhấn phím thoát.
- **Khắc phục triệt để lỗi gạch chân CJK**: Cơ chế `directReplacement` (`insertText:replacementRange:`) giúp nhập liệu mượt mà trên trình duyệt (Chrome, Brave, Edge) và ứng dụng Electron (VS Code, Slack) mà không rung giật con trỏ.
- **Bộ cài đặt kép (DMG & PKG)**:
  - Bản đóng gói PKG với script `postinstall` tự động đăng ký bộ gõ vào macOS Input Sources mà không cần khởi động lại máy.
  - Tệp đĩa `.dmg` thân thiện với người dùng macOS.
- **Bộ nhận diện thương hiệu tối giản**: Bộ biểu tượng hoa Sen cách điệu hình giọt sương và chữ Ṽ, hỗ trợ Dark / Light mode đầy đủ các kích thước (16px đến 1024px).
- **Bộ kiểm thử hồi quy 9,091 từ**: Đạt tỷ lệ chính xác **98.30%** trên bộ dữ liệu kiểm thử thực tế.

### Bảo mật & Riêng tư (Security & Privacy)
- **Zero-Logging Posture**: Loại bỏ hoàn toàn việc ghi log phím gõ ra ổ đĩa (`~/Library/Logs`).
- **Không yêu cầu quyền Accessibility**: Không sử dụng `CGEventTap` hay quyền can thiệp hệ thống.

---

[1.1.0]: https://github.com/stevedat/VieLotus-IM/releases/tag/v1.1.0
[1.0.0]: https://github.com/stevedat/VieLotus-IM/releases/tag/v1.0.0
