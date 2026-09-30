# Nhật ký Thay đổi (Changelog)

Tất cả thay đổi đáng chú ý của dự án **Sen Việt (VieLotusIM)** sẽ được ghi chép tại tệp này theo định dạng chuẩn [Keep a Changelog](https://keepachangelog.com/vi/1.0.0/). Dự án tuân thủ [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-09-30

### Tính năng mới (Added)
- **Kiến trúc Native InputMethodKit**: Tích hợp trực tiếp với macOS Text Input Management qua `IMKInputController` và `NSTextInputClient`.
- **Lõi xử lý tiếng Việt tốc độ cao**: Liên kết Pure Swift engine (`libuvie`) an toàn qua Native Swift, độ trễ xử lý phím từ 10 - 25 µs.
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

[1.0.0]: https://github.com/stevedat/VietLotus-IM/releases/tag/v1.0.0
