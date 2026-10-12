## Tóm tắt thay đổi (Summary of Changes)
<!-- Mô tả ngắn gọn những gì PR này thực hiện -->

## Động lực & Ngữ cảnh (Motivation & Context)
<!-- Liên kết đến Issue liên quan nếu có, ví dụ: Fixes #123 -->

## Danh sách kiểm tra chất lượng (Verification Checklist)
- [ ] Đã chạy `swift build` thành công trên cả 2 kiến trúc (arm64, x86_64).
- [ ] Đã chạy kiểm thử đơn vị: `swift test` (100% pass).
- [ ] Đã chạy kiểm thử hồi quy 9,091 từ: `swift run VieLotusCLI --benchmark` (tỷ lệ vượt ngưỡng >= 98.0%).
- [ ] Không có log debug phím gõ ra đĩa (`DiagnosticLogger` tuân thủ zero-logging).
- [ ] Không có secret, credential hoặc thông tin nhận dạng cá nhân trong commit.
- [ ] Tuân thủ quy tắc mã nguồn mở theo giấy phép Apache 2.0.
