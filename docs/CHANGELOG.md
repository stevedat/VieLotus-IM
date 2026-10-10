# Nhật ký Thay đổi (Changelog)

Tất cả thay đổi đáng chú ý của dự án **Sen Việt (VieLotusIM)** sẽ được ghi chép tại tệp này theo định dạng chuẩn [Keep a Changelog](https://keepachangelog.com/vi/1.0.0/). Dự án tuân thủ [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.1] - 2026-10-10

### Tính năng mới & Cải tiến (Added & Improved)
- **Chuyển đổi Giấy phép sang MIT License**:
  - Toàn bộ dự án chuyển sang chuẩn mã nguồn mở thân thiện nhất hệ sinh thái Apple (**MIT License**), tương thích 100% với Apple App Store và cho phép tái sử dụng lõi `VieLotusCore` qua Swift Package Manager (SPM).
- **Bộ điều phối hiển thị thông minh (Adaptive Presentation Engine)**:
  - **Direct Replacement**: Thay thế trực tiếp không gạch chân trên các ứng dụng AppKit gốc (Pages, TextEdit, Safari, Xcode, Spotlight) và dòng lệnh (Terminal Direct).
  - **Marked Text chuẩn W3C**: Cơ chế gạch chân soạn thảo chuẩn Apple trên các ứng dụng Web / Electron (Chrome, VS Code, Slack, Discord, Notion...). Triệt tiêu hoàn toàn lỗi nuốt chữ, lặp chữ (`t-ti-tiế-tiếng`) và nhảy con trỏ do Virtual DOM diffing. Khi kết thúc từ, văn bản chuyển thành chữ thường sạch sẽ ngay lập tức.
- **Nâng tỷ lệ kiểm thử hồi quy lên 99.99%**:
  - Đạt **9,090 / 9,091 từ (99.99%)** trên bộ kiểm thử hồi quy chính thức.
- **Giao diện Cài đặt Tinh gọn Chuẩn Apple Minimalist**:
  - Làm sạch danh sách ứng dụng mặc định, tối ưu hóa cho người dùng phổ thông (Chrome, Safari, Word, VS Code, Slack, Discord).
  - Tích hợp nút và liên kết truy cập nhanh vào **GitHub Discussions** trực tiếp trong menu và chân trang Cài đặt.
  - Menu trạng thái tự động hiển thị phiên bản động theo `AppInfo.appVersion`.
- **Nền tảng Mở rộng iOS & Macro**:
  - Bổ sung `MacroEngine` và `UIKitInputSessionAdapter` chuẩn bị cho bước mở rộng bàn phím iOS/iPadOS theo lộ trình.

### Sửa lỗi (Fixed)
- **Sửa triệt để lỗi xóa lùi dở từ (Partial Deletion Prefix Retention)**:
  - Khắc phục hoàn toàn tình trạng khi gõ một từ (ví dụ `đổi`, `trường`), sau đó bấm Backspace giữ lại một phần tiền tố (`đ`, `tr`) và gõ tiếp hậu tố (`ược` $\to$ ra đúng `được` thay vì `uocwj`; `ưởng` $\to$ ra `trưởng` thay vì `uowngr`).
  - Tích hợp thuật toán `rawKeys(for:inputMethod:)` phân rã NFD Unicode tái tạo trạng thái ngữ âm chính xác cho tiền tố còn lại.

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

[1.1.1]: https://github.com/stevedat/VieLotus-IM/releases/tag/v1.1.1
[1.1.0]: https://github.com/stevedat/VieLotus-IM/releases/tag/v1.1.0
[1.0.0]: https://github.com/stevedat/VieLotus-IM/releases/tag/v1.0.0
