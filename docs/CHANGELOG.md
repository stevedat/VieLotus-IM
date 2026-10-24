# Nhật ký Thay đổi (Changelog)

Tất cả thay đổi đáng chú ý của dự án **Sen Việt (VieLotusIM & VieLotusIOS)** sẽ được ghi chép tại tệp này theo định dạng chuẩn [Keep a Changelog](https://keepachangelog.com/vi/1.0.0/). Dự án tuân thủ [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-10-12

### 🎉 Phát hành Chính thức Đầu tiên (Official First Release)
Bản phát hành đầu tiên mang tính bước ngoặt của **Sen Việt**, thống nhất toàn diện giải pháp bộ gõ tiếng Việt thuần chuẩn **Apple Native** cho toàn bộ hệ sinh thái **macOS**, **iPadOS** và **iOS**.

---

### 🌸 Điểm Nổi Bật Chính (Key Highlights)

#### 1. Chuẩn Apple Native & An Toàn Bộ Nhớ
- **Pure Apple Native Frameworks**: Hoạt động trực tiếp qua `InputMethodKit` trên macOS và `UIKit` (`UIInputViewController`) trên iOS / iPadOS.
- **Tuyệt đối KHÔNG cần quyền Trợ năng (Accessibility)**: Không sử dụng `CGEventTap`, không giả lập sự kiện phím Carbon cổ điển, không can thiệp sâu vào luồng hệ thống.
- **100% Pure Swift & Memory Safety**: Toàn bộ lõi `VieLotusCore` được viết bằng Swift an toàn bộ nhớ, bất đồng bộ hiện đại, không phụ thuộc vào thư viện C/C++ cổ điển.

#### 2. Khắc Phục Triệt Để Các Lỗi Cố Hữu Của Bộ Gõ Cũ
- **Adaptive Presentation Engine**:
  - *Direct Replacement*: Thay thế trực tiếp không gạch chân trên các ứng dụng AppKit gốc (Pages, TextEdit, Safari, Xcode, Spotlight) và Terminal / CLI hiện đại (Ghostty, Alacritty, Kitty).
  - *Marked Text chuẩn W3C*: Cơ chế gạch chân soạn thảo chuẩn Apple trên các ứng dụng Web / Electron (Chrome, VS Code, Slack, Discord, Notion...). Triệt tiêu hoàn toàn lỗi nuốt chữ, lặp chữ (`t-ti-tiế-tiếng`) và nhảy con trỏ do Virtual DOM diffing. Khi kết thúc từ, văn bản chuyển thành chữ thường sạch sẽ ngay lập tức.
- **Bảo toàn hoàn hảo lệnh Hoàn tác (`Cmd + Z`)**: Hoàn tác từng bước chuẩn xác, không bị xoá mất cả khối văn bản.
- **Sửa triệt để lỗi xóa lùi dở từ (Partial Deletion Prefix Retention)**: Thuật toán `rawKeys(for:inputMethod:)` phân rã NFD Unicode tái tạo trạng thái ngữ âm chính xác cho tiền tố khi nhấn Backspace.

#### 3. Trí Tuệ Song Ngữ Thông Minh (Smart Bilingual)
- **Đạt 99.97% trên bộ kiểm thử hồi quy 9,091 ca gõ thực tế**: Tự động giữ nguyên các từ tiếng Anh và mã code thông dụng mà không bị biến dạng thành dấu tiếng Việt.
- **Ràng buộc Ngữ âm học chặt chẽ (Phonological Constraints)**:
  - Luật âm cuối tắc (`-c, -ch, -p, -t` bắt buộc phải mang thanh Sắc hoặc Nặng), loại bỏ triệt để các trường hợp gõ lỗi từ tiếng Anh thành âm tiết rác như `mêt`, `sỏt`, `heảt`, `pỏt`, `chủch`.
  - Bộ lọc nguyên âm đôi / nguyên âm ba không tồn tại trong tiếng Việt (`ae`, `ea`, `io`...).
  - Bộ đệm từ điển tiếng Anh LRU 65,536 mục, giải quyết nghẽn IPC `NSSpellServer` và tối ưu hóa thời gian phản hồi.
- **Khoá kiểm thử đối xứng `vn_survives_collision`**: Đảm bảo bảo vệ trọn vẹn các âm tiết tiếng Việt thuần túy.

#### 4. Bàn phím iOS & Container App (`VieLotusApp` & `VieLotusKeyboard`)
- **Giao diện bàn phím UIKit thuần (`KeyboardLayoutView`)**:
  - Hỗ trợ đầy đủ các tầng ký tự: chữ hoa/thường, số, ký tự đặc biệt, phím Globe chuyển đổi bộ gõ, Delete, Return, Space.
  - Phản hồi rung xúc giác tinh tế (`UIImpactFeedbackGenerator`).
- **Thanh từ gợi ý sắc nét (`CandidateBarView`)**: Hiển thị từ ghép và từ gợi ý độ nét cao, tương thích hoàn hảo Light & Dark mode.
- **Chế độ Con trỏ Trackpad trên phím Space (Spacebar Trackpad Mode)**: Nhấn giữ phím Space 0.22s để kích hoạt chế độ rê con trỏ mượt mà chuẩn Apple, tự động cam kết từ đang soạn trước khi di chuyển caret.
- **Ứng dụng SwiftUI Container (`VieLotusAppIOS`)**:
  - Tab Kích hoạt trực quan 4 bước.
  - Tab Gõ thử (Playground) kèm chip câu mẫu.
  - Tab Cài đặt kiểu gõ Telex / VNI, bỏ dấu hiện đại, bật/tắt gõ tắt, haptics.
  - Quản lý bảng gõ tắt cá nhân đồng bộ qua App Group `group.com.vietlotus.keyboard`.
- **Sẵn sàng cho App Store & TestFlight**: Đạt chuẩn `RequestsOpenAccess = false` (100% Offline, bảo mật tối đa, không cần Allow Full Access), `ITSAppUsesNonExemptEncryption = false`.

#### 5. Bảng Gõ Tắt Cá Nhân (Personal Macro Editor)
- Trình quản lý gõ tắt chuẩn phong cách Apple Minimalist trên cả macOS và iOS.
- Tự động lưu và đồng bộ `macros.json`.
- Tích hợp sẵn hàng loạt từ viết tắt công việc, giao tiếp và địa danh Việt Nam phổ biến.

#### 6. Bộ Công Cụ Chẩn Đoán & Lab (`VieLotusLab`)
- Ứng dụng độc lập quan sát nhịp gõ phím và sự kiện `AXUIElement` trên các ứng dụng ngoài.
- Bảo vệ quyền riêng tư nghiêm ngặt: Tự động che mờ (masking) nội dung tài liệu, chỉ ghi lại chuỗi phím tester nhập trong phiên chẩn đoán.
- Xuất báo cáo lỗi khép kín (JSON & Markdown) đính kèm đầy đủ thông tin môi trường.

#### 7. Bảo Mật & Quyền Riêng Tư Tuyệt Đối (Zero-Logging Posture)
- Hoạt động 100% Offline, không gửi bất kỳ dữ liệu nào qua mạng.
- Tuyệt đối không ghi nhật ký phím gõ ra đĩa (`os.Logger` chỉ ở chế độ DEBUG, không I/O file).
- Mã nguồn mở theo giấy phép **MIT License** thân thiện nhất cho cộng đồng.

---

[1.0.0]: https://github.com/stevedat/VieLotus-IM/releases/tag/v1.0.0
