# VieLotusIM (Sen Việt)

Bộ gõ tiếng Việt cho macOS, Windows và Linux.

Kho này có engine Swift và lớp InputMethodKit cho macOS, cùng engine C++20 và lớp tích hợp cho Windows, Linux. Ứng dụng iOS và Android được phân phối riêng; mã nguồn ứng dụng không nằm trong kho này.

## Nền tảng

| Nền tảng | Mã nguồn trong kho | Tải ứng dụng |
| --- | --- | --- |
| macOS | Engine Swift và lớp InputMethodKit | [Bản phát hành mới nhất](https://github.com/stevedat/VieLotus-IM/releases/latest) |
| Windows | Engine C++20 và lớp TSF | [Bản phát hành mới nhất](https://github.com/stevedat/VieLotus-IM/releases/latest) · [Microsoft Store](https://apps.microsoft.com/detail/9PF5K64GXXSH) |
| Linux | Engine C++20, IBus/Fcitx5 và gói Debian | [Cài trên Ubuntu/Debian/Arch](docs/INSTALL_LINUX.vi.md) · [Bản phát hành mới nhất](https://github.com/stevedat/VieLotus-IM/releases/latest) |
| iOS/iPadOS | Không có mã nguồn ứng dụng trong kho | [App Store](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799) |
| Android | Không có mã nguồn ứng dụng trong kho | [Google Play](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard) |

## Biên dịch và kiểm chứng

Yêu cầu: macOS 13 trở lên và bộ công cụ Swift 6.

```sh
swift test
swift run VieLotusCLI --benchmark
swift build --product VieLotusIM
./scripts/build_imk.sh
```

SwiftPM biên dịch từ source có trong kho, không tải engine nhị phân riêng. Package dùng chế độ ngôn ngữ Swift 5 để tương thích mã nguồn.

Hướng dẫn build Linux và Windows nằm trong [`CrossPlatform`](CrossPlatform/). Tệp đóng gói Debian ở [`CrossPlatform/packaging/debian`](CrossPlatform/packaging/debian/).

## Trạng thái kiểm thử

CI đã kiểm tra gõ qua IBus/Fcitx5 trong widget GTK3 và Qt5 trên Ubuntu. Maintainer cũng báo cáo đã kiểm thử thủ công trên macOS, Windows, Ubuntu ARM64 và Linux Mint, cùng kết quả gõ tốt trong nhiều ứng dụng. Ứng dụng iOS và Android đã có trên store chính thức. Xem [trạng thái kiểm thử và phạm vi bằng chứng](docs/TEST_STATUS.md) và [danh sách kiểm tra ứng dụng macOS](docs/FIELD_TEST_CHECKLIST.md).

## Kết quả benchmark

Đo ngày 14/11/2026 trên source snapshot đi kèm README bằng `swift run VieLotusCLI --benchmark --json`:

| Chỉ số | Kết quả |
| --- | ---: |
| Bộ hồi quy chính | 9.091 / 9.091 (100,00%) |
| Va chạm song ngữ không ngữ cảnh | 365 / 373 (97,86%) |
| Đường gõ tiếng Việt duy nhất (`whitelist_safe = never`) | 180 / 180 (100,00%) |

Đây là kết quả của bộ kiểm thử hồi quy, không có nghĩa bộ gõ không lỗi trong mọi ứng dụng hoặc thiết bị. Xem điều kiện đo tại [`docs/BENCHMARK_REPORT.md`](docs/BENCHMARK_REPORT.md).

## Quyền riêng tư

Engine xử lý nội dung gõ trên thiết bị. Trình cập nhật macOS kết nối GitHub để kiểm tra bản phát hành; biểu mẫu feedback tùy chọn gửi báo cáo tới dịch vụ được cấu hình. Xem [`PRIVACY.md`](PRIVACY.md).

## Giấy phép

Source của dự án trong kho này theo [MIT](LICENSE), trừ thành phần bên thứ ba có thông báo và điều khoản riêng trong [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) và tệp bản quyền Debian. Ứng dụng iOS và Android phân phối riêng, không thuộc kho này và không nằm trong tuyên bố giấy phép trên.

## Liên kết

- [Kiến trúc](docs/ARCHITECTURE.md)
- [Chính sách quyền riêng tư](PRIVACY.md)
- [Lịch sử phát hành](https://github.com/stevedat/VieLotus-IM/releases)
- [Báo lỗi](https://github.com/stevedat/VieLotus-IM/issues)
