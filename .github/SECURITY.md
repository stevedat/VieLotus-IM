# Chính sách Bảo mật (Security Policy)

## Cam kết Quyền riêng tư & An toàn Thông tin

Bộ gõ **Sen Việt (VieLotusIM)** được thiết kế theo triết lý **Zero-Telemetry & Zero-Logging**:

1. **Không ghi log phím gõ (Zero Keystroke Logging)**: 
   - Ứng dụng không bao giờ lưu trữ nội dung phím gõ của người dùng ra đĩa (`~/Library/Logs` hoặc bất kỳ tệp cục bộ nào).
   - Nhật ký chẩn đoán chỉ sử dụng `os.Logger` trong các bản dựng thử nghiệm (`#if DEBUG`) và bị loại bỏ hoàn toàn trong bản phát hành chính thức (Release).
2. **Không kết nối mạng (Zero Network Access)**:
   - Ứng dụng không chứa bất kỳ mã nguồn mạng (URLSession, Socket, WebSockets) nào để gửi dữ liệu ra bên ngoài.
   - Hoàn toàn hoạt động cục bộ (offline) 100%.
3. **Không đòi hỏi quyền trợ năng xâm lấn (No Accessibility Permissions)**:
   - Ứng dụng sử dụng chuẩn gốc `InputMethodKit` của macOS thay vì `CGEventTap` hay Accessibility (`AXIsProcessTrusted`), đảm bảo cô lập theo đúng quyền hạn do hệ điều hành cấp.

---

## Các phiên bản được hỗ trợ (Supported Versions)

| Phiên bản | Trạng thái bảo mật |
| :--- | :---: |
| 1.0.x (Hiện tại) | :white_check_mark: Được hỗ trợ |
| < 1.0.0 | :x: Hết vòng đời |

---

## Báo cáo lỗ hổng (Reporting a Vulnerability)

Nếu bạn phát hiện bất kỳ vấn đề bảo mật nào liên quan đến Sen Việt:

1. **Vui lòng KHÔNG mở công khai Issue trên GitHub**.
2. Gửi thông tin chi tiết qua tính năng [GitHub Security Advisories](https://github.com/stevedat/VietLotus-IM/security/advisories/new) hoặc liên hệ qua email bảo mật của dự án.
3. Vui lòng cung cấp:
   - Mô tả chi tiết về lỗ hổng hoặc hành vi bất thường.
   - Phiên bản macOS và phiên bản VieLotusIM đang sử dụng.
   - Các bước cụ thể để tái hiện vấn đề (PoC).

Chúng tôi cam kết phản hồi trong vòng **48 giờ** và phối hợp xử lý bản vá theo quy trình tiết lộ có trách nhiệm (Responsible Disclosure).
