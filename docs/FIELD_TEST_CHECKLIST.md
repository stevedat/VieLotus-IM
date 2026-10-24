# VieLotusIM (Sen Việt) — Field Test Matrix & Sign-Off Checklist
*Tài liệu Quy chuẩn Kiểm thử & Nghiệm thu Thực địa Ứng dụng macOS*

---

## 1. Mục tiêu & Nguyên tắc Nghiệm thu (Objectives & Principles)

Bộ gõ tiếng Việt trên macOS thường đạt điểm số hoàn hảo trong môi trường kiểm thử dòng lệnh (CLI harness), nhưng lại phát sinh lỗi khi tương tác với các ứng dụng thực tế do sự khác biệt trong cách các Host Application triển khai giao thức `IMKServer` và `IMKTextInput`.

Tài liệu này chuẩn hóa **Ma trận Kiểm thử Thực địa (Field Test Matrix)** và **Quy trình Nghiệm thu 8 Nhóm Ứng dụng Trọng yếu** nhằm nâng mức độ tin cậy của Sen Việt (VieLotusIM) từ cấp thiết kế (85–90%) lên cấp độ sản phẩm xuất xưởng (95–99%).

### Nguyên tắc Bất biến (Zero-Compromise Invariants):
1. **Pure Native IMKit**: Hoạt động 100% qua `InputMethodKit`, **tuyệt đối không dùng Accessibility (`CGEventTap`)** để can thiệp bàn phím.
2. **Zero Character Dropping**: Không nuốt ký tự khi gõ lướt tốc độ cao (>80 WPM).
3. **Zero Duplication / Stutter**: Không lặp chữ (`t-ti-tiế-tiếng`) trên các khung soạn thảo web/Electron.
4. **Zero Desync / Caret Jumping**: Không nhảy con trỏ về đầu dòng khi gõ dấu hoặc hoàn tác (Backspace).

---

## 2. Ma trận Phân loại Ứng dụng & Chế độ Trình diễn (Application Presentation Matrix)

Sen Việt tự động phân loại ứng dụng máy chủ thông qua `ClientAdapter.swift` và cấu hình `typing-modes.yml`:

| Nhóm Ứng dụng | Ứng dụng Đại diện | Chế độ Trình diễn Quy định | Cơ chế Giao tiếp Hệ thống |
| :--- | :--- | :--- | :--- |
| **1. Apple Native (AppKit / Cocoa)** | Safari, Apple Notes, Pages, Mail, TextEdit, Xcode, Finder | `Direct Replacement` | Ghi trực tiếp qua `insertText(_:replacementRange:)`, không gạch chân, tích hợp Undo (`Cmd+Z`) tự nhiên. |
| **2. Trình duyệt Web (Chromium & WebKit)** | Google Chrome, Microsoft Edge, Arc, Brave, Opera | `Marked Text` (W3C Standard) | Đồng bộ sự kiện `compositionstart / compositionupdate / compositionend` với DOM JavaScript. |
| **3. Khung ứng dụng Electron / CEF** | VS Code, Slack, Discord, Notion, Obsidian, Telegram Desktop, Zalo | `Marked Text` | Cô lập bộ đệm soạn thảo, loại trừ hoàn toàn xung đột React / Virtual DOM diffing. |
| **4. Terminal Emulators Hiện đại** | Ghostty, iTerm2, Alacritty, Kitty, Terminal.app | `Terminal Direct` / `Marked Text` | Đồng bộ UTF-16 code units, phát tín hiệu xóa PTY `\u{7F}` tức thời, không phá vỡ `zsh-autosuggestions`. |
| **5. Bộ ứng dụng Văn phòng (Office)** | Microsoft Word, Excel, PowerPoint | `Direct Replacement` | Điều hướng con trỏ chính xác trong ô tính (Excel) và văn bản phức tạp (Word). |
| **6. Trình tìm kiếm & Lớp phủ (Overlays)** | Spotlight, Raycast, Alfred | `Direct Replacement` | Phản hồi tức thì trong ô tìm kiếm một dòng, không khóa vùng chọn. |
| **7. Thiết kế Đồ họa & Canvas** | Figma, Adobe Photoshop / Illustrator, Canva | `Marked Text` / Dynamic Fallback | Tự động chuyển fallback khi client trả về `NSNotFound` cho caret position. |

---

## 3. Danh mục Ca Kiểm thử Hành vi Thực tế (Field Test Cases)

### FT-01: Gõ lướt Tốc độ cao (Rapid Burst Typing >80 WPM)
* **Mục tiêu**: Kiểm tra tính ổn định của luồng bất đồng bộ và bộ nhớ đệm `InputSessionManager`.
* **Thao tác**: Gõ đoạn văn bản tiếng Việt dài với tốc độ liên tục không ngắt quãng (trên 80 từ/phút) trên Google Chrome và TextEdit:
  > *"Trăm năm trong cõi người ta, chữ tài chữ mệnh khéo là ghét nhau. Trải qua một cuộc bể dâu, những điều trông thấy mà đau đớn lòng."*
* **Tiêu chuẩn Đạt (PASS)**:
  - Tất cả các ký tự xuất hiện đúng thứ tự, không bị nuốt bất kỳ phím nào.
  - Dấu thanh và mũ/móc xuất hiện mượt mà theo thời gian thực (độ trễ hiển thị <16ms).

---

### FT-02: Hoàn tác Sửa lùi Lưng chừng (Mid-Word Backspace & Mutation)
* **Mục tiêu**: Xác thực không xảy ra hiện tượng lệch đồng bộ (`REPLAY_DESYNC`) hoặc vướng rác màn hình.
* **Thao tác**:
  1. Gõ `truong` $\rightarrow$ nhận `truong`.
  2. Bấm phím Backspace 2 lần $\rightarrow$ buffer còn `tru`.
  3. Gõ tiếp `yeenf` $\rightarrow$ mong đợi hiển thị `truyền`.
  4. Gõ `toans` $\rightarrow$ hiển thị `toán`, bấm Backspace 1 lần $\rightarrow$ còn `toan`, gõ tiếp `f` $\rightarrow$ mong đợi hiển thị `toàn`.
* **Tiêu chuẩn Đạt (PASS)**:
  - Ký tự bị xóa hoàn toàn sạch sẽ, không để lại ký tự dư thừa hoặc khoảng trắng giả.
  - Quy tắc biến đổi âm tiết mới được áp dụng chính xác ngay trên buffer đã chỉnh sửa.

---

### FT-03: Trình Soạn thảo Web & Khung Chat React (Draft.js, Slate, Lexical, Quill)
* **Mục tiêu**: Triệt tiêu lỗi lặp từ kinh điển trên web khi sử dụng bàn phím tiếng Việt.
* **Ứng dụng kiểm thử**: Khung chat Slack Web/Desktop, Facebook Messenger trên Chrome, Google Docs, khung gõ Notion.
* **Thao tác**: Gõ nhanh các từ ghép tiếng Việt có dấu:
  > *"tiếng Việt", "chuyên nghiệp", "tuyển dụng", "nghiêng ngả", "phương hướng"*
* **Tiêu chuẩn Đạt (PASS)**:
  - Tuyệt đối không xuất hiện hiện tượng lặp chữ: `t-ti-tiế-tiếng Việt` hay `ch-chuy-chuyên`.
  - Khi gõ phím Cách (Space) kết thúc từ, gạch chân `markedText` biến mất ngay lập tức.

---

### FT-04: Thanh Địa chỉ Trình duyệt có Tự động Hoàn thành (Omnibox Autocomplete)
* **Mục tiêu**: Kiểm tra xung đột giữa cơ chế gợi ý URL của trình duyệt và bộ đệm từ đang gõ.
* **Ứng dụng kiểm thử**: Thanh URL của Google Chrome, Safari, Arc.
* **Thao tác**: Gõ tên miền tiếng Việt và URL có cấu trúc tiếng Anh:
  > `dantri.com.vn`, `vnexpress.net`, `github.com/apple/swift`
* **Tiêu chuẩn Đạt (PASS)**:
  - Khi gõ dấu chấm `.` hoặc gạch chéo `/`, từ trước đó tự động commit nguyên vẹn.
  - Tính năng inline autocomplete của trình duyệt không làm biến dạng từ tiếng Việt hoặc nuốt phím kế tiếp.

---

### FT-05: Môi trường Lập trình & Terminal (Developer Workflow)
* **Mục tiêu**: Bảo đảm an toàn tuyệt đối cho lập trình viên khi gõ code xen lẫn tiếng Việt.
* **Ứng dụng kiểm thử**: VS Code, Cursor, Ghostty, iTerm2, Terminal.app.
* **Thao tác**:
  1. Gõ chuỗi định danh biến: `user_name`, `get_post_id`, `max_value`, `class_name`.
  2. Gõ lệnh CLI chứa cờ: `docker-compose up -d`, `git commit -m "fix: sửa lỗi giao diện"`.
  3. Gõ trong Terminal khi bật plugin `zsh-autosuggestions`.
* **Tiêu chuẩn Đạt (PASS)**:
  - Dấu gạch dưới `_`, gạch ngang `-` và dấu nháy kép `"` kích hoạt ngắt từ sạch sẽ.
  - Các từ khóa tiếng Anh không bị nhận diện nhầm thành âm tiết tiếng Việt (`post` không thành `pót`, `user` không thành `usẻ`).
  - Terminal không bị nhân đôi ký tự và không làm hỏng dòng nhắc shell.

---

### FT-06: Phím Xác nhận Enter & Phím Điều hướng Mũi tên (Caret Navigation)
* **Mục tiêu**: Kiểm tra trạng thái kết thúc phiên soạn thảo khi gửi tin nhắn hoặc chuyển dòng.
* **Thao tác**:
  1. Trong Slack hoặc Telegram, gõ `Chào buổi sáng` và bấm ngay phím **Enter**.
  2. Trong Apple Notes, gõ `Hà Nội mùa thu`, bấm phím **Mũi tên Trái** 3 lần rồi gõ thêm ký tự.
* **Tiêu chuẩn Đạt (PASS)**:
  - Phím Enter commit chính xác từ cuối cùng và gửi tin nhắn trong 1 thao tác duy nhất (không phải bấm Enter 2 lần).
  - Phím mũi tên giải phóng hoàn toàn vùng soạn thảo dở dang, cho phép con trỏ di chuyển tự do.

---

### FT-07: Khôi phục Đa tầng (Cmd+Z Native Undo Stack)
* **Mục tiêu**: Tích hợp hoàn hảo với hệ thống Undo của macOS AppKit.
* **Ứng dụng kiểm thử**: Apple Notes, Pages, TextEdit.
* **Thao tác**:
  1. Gõ một câu hoàn chỉnh: *"Sen Việt mang lại trải nghiệm gõ tự nhiên."*
  2. Bấm tổ hợp phím **Cmd+Z**.
* **Tiêu chuẩn Đạt (PASS)**:
  - Lệnh Undo hoàn tác nguyên một từ gần nhất, không phải hoàn tác từng nét gõ hoặc từng chữ cái lẻ loi.
  - Bấm tiếp **Shift+Cmd+Z** (Redo) phục hồi lại chính xác từ đó.

---

## 4. Bảng Kiểm Nghiệm Thu Từng Ứng Dụng (Field Acceptance Sheet)

Đánh dấu `[x]` vào ô kiểm khi ứng dụng đã vượt qua toàn bộ 7 ca kiểm thử phía trên:

| # | Tên Ứng dụng | Phiên bản Kiểm thử | Chế độ Thực tế | Kết quả Nghiệm thu | Ký duyệt (Sign-Off) |
| :-: | :--- | :--- | :--- | :-: | :-: |
| 1 | **Apple Safari** | 18.0+ | Direct Replacement | [ ] PASS | ________ |
| 2 | **Apple Notes** | macOS 15.0+ | Direct Replacement | [ ] PASS | ________ |
| 3 | **Google Chrome** | 130.0+ | Marked Text | [ ] PASS | ________ |
| 4 | **VS Code / Cursor** | 1.94+ | Marked Text | [ ] PASS | ________ |
| 5 | **Slack Desktop** | 4.40+ | Marked Text | [ ] PASS | ________ |
| 6 | **Ghostty / iTerm2** | Latest Stable | Terminal Direct | [ ] PASS | ________ |
| 7 | **Microsoft Word** | 16.89+ (365) | Direct Replacement | [ ] PASS | ________ |
| 8 | **Raycast / Spotlight**| Latest Stable | Direct Replacement | [ ] PASS | ________ |

---

## 5. Sử dụng VieLotusLab để Phân tích & Bắt vết Lỗi (Diagnostics via VieLotusLab)

Khi phát hiện ứng dụng có hành vi bất thường:
1. Mở công cụ **VieLotusLab** (`./scripts/build_lab.sh` hoặc chạy trực tiếp từ `DerivedData`).
2. Chọn ứng dụng mục tiêu trong danh sách tiến trình AX.
3. Kích hoạt tính năng **Event Recording** để ghi lại luồng sự kiện:
   - Nhãn Bundle ID & AXRole của trường nhập liệu.
   - Luồng sự kiện `insertText:replacementRange:` và `setMarkedText:selectionRange:`.
4. Xuất gói chẩn đoán **Diagnostic Bundle (.json)** và đính kèm vào báo cáo lỗi để đội ngũ kỹ thuật cập nhật quy tắc trong `Sources/VieLotusCore/Resources/typing-modes.yml`.
