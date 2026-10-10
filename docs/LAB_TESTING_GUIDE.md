# Hướng Dẫn Kiểm Thử Lab & Báo Cáo Lỗi (VieLotus Tester Guide)

Tài liệu này cung cấp quy trình 6 bước khép kín dành cho người dùng và tester bên ngoài tham gia trải nghiệm, kiểm thử và gửi báo cáo lỗi có thể xử lý được cho dự án **Sen Việt (VieLotusIM)** và công cụ chẩn đoán **VieLotus Lab**.

---

## 1. Chuẩn Bị & Cài Đặt (Installation)

Tất cả các bản phát hành chính thức của Sen Việt đều được Apple Notary Service công chứng và ký số bởi Developer ID `NIDO HOLDINGS NEXT GENERATION COMPANY LIMITED (9QCZ4F58K8)`.

### 1.1 Tải bộ cài đặt chính thức
Truy cập trang [Releases chính thức trên GitHub](https://github.com/stevedat/VieLotus-IM/releases):
- **`VieLotusIM.pkg`** (khuyên dùng): Bộ cài đặt tự động đăng ký nguồn nhập (có từ bản `v1.0.0`).
- **`VieLotusLab.dmg`**: Ứng dụng phòng thí nghiệm chẩn đoán nhịp gõ dành cho Tester (phát hành chính thức từ bản `v1.1.0+` hoặc bản thử nghiệm).

> [!NOTE]
> Bản phát hành ban đầu `v1.0.0` chỉ bao gồm 3 tệp cài đặt của bộ gõ `VieLotusIM`. Công cụ chẩn đoán `VieLotusLab.dmg` và tệp đối chiếu `checksums.sha256` được cung cấp chính thức từ phiên bản `v1.1.0+`.

### 1.2 Kiểm tra tính toàn vẹn & Chữ ký số Apple
Mỗi bản Release từ `v1.1.0+` đều đính kèm tệp `checksums.sha256`. Bạn có thể mở Terminal và kiểm tra toàn bộ 5 tệp bằng script kiểm tra nghiêm ngặt:
```bash
# Kiểm tra đối chiếu mã băm SHA-256
shasum -a 256 -c checksums.sha256

# Hoặc chạy công cụ kiểm tra chữ ký số và Notarization của toàn bộ gói:
./scripts/verify_release_assets.sh
```

---

## 2. Kích Hoạt Nguồn Nhập (Activation)

Nếu cài bằng gói `VieLotusIM.pkg`, bộ gõ sẽ tự động được thêm vào hệ thống. Nếu cài lần đầu trên một máy Mac mới tinh:
1. **Khởi động lại hoặc Đăng xuất (Log Out)**: Đăng xuất tài khoản macOS và đăng nhập lại 1 lần để `TextInputMenuAgent` nhận diện bộ gõ mới.
2. Mở **Cài đặt hệ thống (System Settings)** $\rightarrow$ **Bàn phím (Keyboard)** $\rightarrow$ **Nguồn nhập (Text Input)** $\rightarrow$ Nhấn **Sửa (Edit...)**.
3. Nhấn dấu `+`, chọn **Tiếng Việt**, chọn **Sen Việt (VieLotusIM)** và nhấn **Thêm (Add)**.
4. Chuyển nguồn nhập sang Sen Việt trên thanh Menu Bar (hoặc phím tắt chuyển bàn phím `Ctrl + Space` / `Caps Lock`).

---

## 3. Ma Trận Thử Nghiệm Chuẩn (Testing Matrix)

Hãy thử nghiệm lần lượt 5 kịch bản tiêu chuẩn đại diện cho các nhóm ứng dụng cốt lõi:

| Nhóm ứng dụng | Ứng dụng mẫu | Thao tác kiểm tra | Tiêu chuẩn ĐẠT |
| :--- | :--- | :--- | :--- |
| **AppKit / Cocoa** | TextEdit, Apple Notes, Safari | Gõ đoạn: `Tiếng Việt thân yêu hoà bình` | Không nhấp nháy gạch chân (zero flicker), đúng vị trí dấu, Cmd+Z hoàn tác mượt. |
| **Chromium / Electron** | Chrome, Cursor, VS Code, Slack | Gõ trong ô URL, form chat, comment code | Chèn chữ tức thời, con trỏ phím không nhảy lung tung, không nuốt phím. |
| **Văn phòng (Office)** | Microsoft Word, Excel, Pages | Gõ câu dài có chứa số và dấu chấm câu | Không kẹt ký tự, gõ nhanh không bị đảo lộn thứ tự chữ cái. |
| **Dòng lệnh (Terminal)** | Terminal.app, iTerm2, Warp | Gõ lệnh: `git commit -m "kiểm tra"` | Hiển thị chữ đang soạn thảo chuẩn xác inline, xoá Backspace mượt. |
| **Bôi đen thay thế** | Bất kỳ ô nhập nào | Bôi đen một từ cũ và gõ từ mới đè lên | Từ cũ biến mất ngay lập tức, từ mới thay thế sạch sẽ không để lại chữ ma. |

---

## 4. Ghi Lại Lỗi & Xuất Gói Chẩn Đoán (Diagnostic Packet)

Khi phát hiện chữ gõ sai, nuốt phím hoặc xung đột, bạn có 2 cách xuất dữ liệu lỗi:

### Cách 1: Sử dụng VieLotus Lab (Khuyên dùng khi lỗi phức tạp)
> [!IMPORTANT]
> **Quy tắc an toàn quyền riêng tư khi thử nghiệm:**
> - Để đảm bảo an toàn tuyệt đối, **hãy mở một ô nhập trống hoặc tài liệu mới** trong ứng dụng mục tiêu khi gõ thử.
> - Lab áp dụng cơ chế lọc riêng tư: chỉ ghi nhận phần ký tự gõ thêm hoặc xóa (delta), tuyệt đối không lưu nội dung tài liệu có sẵn vào tệp chẩn đoán.

1. Mở ứng dụng **VieLotus Lab** từ file DMG hoặc thư mục Applications.
2. Chọn tab **"Theo dõi ứng dụng"**:
   - Nếu chưa cấp quyền Trợ năng, bấm **"Mở Cài đặt hệ thống"** và bật công tắc cho *VieLotus Lab*.
   - Trong menu thả xuống *Mục tiêu*, chọn ứng dụng đang gặp lỗi (ví dụ: `Cursor [Chromium]`, `Microsoft Word [Office]`).
   - Nhấn **"Bắt đầu theo dõi"**.
3. Chuyển sang ứng dụng mục tiêu và gõ lại chuỗi phím gây lỗi.
4. Quay lại VieLotus Lab:
   - Nhấn **"Xem trước & Báo cáo"**: Cửa sổ kiểm tra và biên tập sẽ hiện ra, cho phép bạn đọc toàn bộ nội dung, tự do xóa bỏ bất kỳ dòng nào trước khi nhấn **"Sao chép vào Clipboard"** hoặc **"Lưu file .md"**.
   - Hoặc nhấn **"Xuất gói JSON"**: Lưu tệp `.json` chứa schema chuẩn `diagnostic_schema_version: 1.0` (các trường văn bản tài liệu đã được tự động ẩn danh hóa `[REDACTED]`).

### Cách 2: Sử dụng Cài đặt Sen Việt (Nhanh, không cần cài Lab)
1. Nhấp vào biểu tượng hoa sen `Ṽ` trên Menu Bar $\rightarrow$ Chọn **Cài đặt...**.
2. Cuộn xuống mục **"CHẨN ĐOÁN & HỖ TRỢ"**:
   - Nhấn **"Sao chép cấu hình"**: Clipboard sẽ lưu khối Markdown chứa phiên bản macOS, kiến trúc CPU, phiên bản app, commit hash và các toggle đang bật/tắt.
   - Nhấn **"Báo lỗi GitHub"** để mở thẳng trang tạo Issue.

---

## 5. Tạo GitHub Issue Báo Cáo Lỗi

1. Truy cập [Trang tạo Issue mới](https://github.com/stevedat/VieLotus-IM/issues/new?template=bug_report.md).
2. Chọn template **Báo cáo lỗi (Bug Report)**.
3. Dán nội dung Markdown đã kiểm tra từ **VieLotus Lab** hoặc **Cài đặt Sen Việt** vào mục tương ứng.
4. Điền chuỗi phím bấm mẫu, kết quả thực tế, kết quả mong đợi và tần suất xảy ra.

> [!CAUTION]
> **Rà soát quyền riêng tư trước khi gửi (Privacy Checklist):**
> - VieLotusIM và VieLotus Lab áp dụng chính sách **Zero-logging** (không tự ghi âm thầm dữ liệu người dùng).
> - Gói chẩn đoán chỉ ghi lại đúng chuỗi phím và thao tác bạn đã gõ trong phiên thử nghiệm.
> - Vui lòng kiểm tra lại nội dung trong cửa sổ xem trước trước khi bấm *Submit new issue*, đảm bảo **không chứa mật khẩu, token bí mật, họ tên thật, số điện thoại hay email cá nhân**.

Nếu bạn có câu hỏi, ý kiến đóng góp tính năng hoặc thảo luận chung, vui lòng tham gia [GitHub Discussions](https://github.com/stevedat/VieLotus-IM/discussions).

---

## 6. Gỡ Cài Đặt Hoặc Quay Về Bộ Gõ Cũ (Rollback / Uninstallation)

Nếu bạn cần gỡ bỏ bản thử nghiệm hoặc quay lại bộ gõ mặc định của macOS:

### 6.1 Tắt nguồn nhập
1. Mở **Cài đặt hệ thống (System Settings)** $\rightarrow$ **Bàn phím** $\rightarrow$ **Nguồn nhập**.
2. Chọn **Sen Việt (VieLotusIM)** và nhấn nút `-` (Xóa).
3. Chọn lại bộ gõ mong muốn (ví dụ: *Simple Telex* hoặc *Vietnamese* mặc định của Apple).

### 6.2 Xóa sạch tệp nhị phân
Mở Terminal và chạy lệnh sau để dọn dẹp sạch sẽ:
```bash
# Xoá ứng dụng bộ gõ khỏi thư mục hệ thống
sudo rm -rf "/Library/Input Methods/VieLotusIM.app"
rm -rf ~/Library/Input\ Methods/VieLotusIM.app

# Tắt tiến trình nền nếu còn sót
killall -9 VieLotusIM 2>/dev/null || true

# Xoá VieLotus Lab nếu không còn nhu cầu sử dụng
rm -rf "/Applications/VieLotus Lab.app"
```
Bộ gõ Sen Việt không cài đặt kernel extension, không can thiệp sâu hệ thống, việc gỡ bỏ diễn ra tức thì và an toàn 100%.
