# Sen Việt (VieLotusIM) — Quy Chuẩn Thương Hiệu & Thiết Kế

Tài liệu quy chuẩn giao diện và nhận diện thương hiệu cho dự án mã nguồn mở **Sen Việt (VieLotusIM)** theo giấy phép **Apache License 2.0**.

---

## 1. Định Danh Dự Án

* **Tên hiển thị:** Sen Việt
* **Tên kỹ thuật:** `VieLotusIM`
* **Hệ sinh thái:** `YouPersona.com`
* **Giấy phép:** Apache License 2.0
* **Triết lý:** Native, Tối giản, Không gạch chân CJK, Không quyền Trợ năng, Zero-Logging.

---

## 2. Bảng Màu Tối Giản (Design Tokens)

| Màu sắc | Mã HEX | Mục đích sử dụng |
| :--- | :---: | :--- |
| **Lotus Accent** | `#FF5E8E` | Màu nhận diện chính, điểm nhấn hoa sen |
| **Deep Magenta** | `#A828B8` | Chuyển sắc gradient biểu tượng |
| **Royal Indigo** | `#4F46E5` | Màu công nghệ, điểm kết thúc gradient |
| **Background Dark** | `#090714` | Nền tối sâu OLED |
| **Card Surface** | `rgba(255, 255, 255, 0.03)` | Bề mặt thẻ kính mờ |
| **Border Subtle** | `rgba(255, 255, 255, 0.08)` | Đường viền mảnh 1px |

```css
/* Gradient thương hiệu */
background: linear-gradient(135deg, #FF5E8E 0%, #A828B8 50%, #4F46E5 100%);
```

---

## 3. Typography & Câu Từ

* **Phông hệ thống:** `-apple-system`, `SF Pro Display`, `SF Pro Text`.
* **Quy chuẩn câu từ:**
  * Viết câu thông thường (sentence case). Không viết hoa toàn bộ (ALL CAPS).
  * Câu từ ngắn gọn, kỹ thuật chính xác, khiêm tốn, không quảng cáo phóng đại.
  * Thông số nhận diện duy nhất trên chân trang: `YouPersona.com`.

---

## 4. Danh Mục Tài Nguyên Vector & Hình Ảnh (`docs/assets/`)

* **Biểu tượng gốc:** `docs/assets/symbol.svg`
* **Favicon tab web:** `docs/assets/favicon.svg` (hoặc `favicon-32x32.png`)
* **Logo thanh điều hướng:** `docs/assets/logo.svg` (Dark) / `logo-light.svg` (Light)
* **Social Preview Card:** `docs/assets/og-card.png` (1200×630)
* **Icon ứng dụng macOS:** `Sources/VieLotusIM/Resources/AppIcon.icns`
