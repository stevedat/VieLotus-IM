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

## Đóng góp ngược dòng (Upstream)

Các bản vá lỗi biên, kiểm thử đơn vị và đóng gói gửi về các dự án mã nguồn mở cùng hệ sinh thái (sổ cái đầy đủ tại [`docs/ECOSYSTEM_CONTRIBUTIONS.vi.md`](docs/ECOSYSTEM_CONTRIBUTIONS.vi.md)):

| Dự án & Người duy trì | PR & Trạng thái trực tiếp | Lỗi / Ca biên kỹ thuật đóng góp |
| :--- | :--- | :--- |
| **[VietTelex](https://github.com/ptrinh/viettelex)** · Phil Trịnh ([@ptrinh](https://github.com/ptrinh)) | [![#133](https://img.shields.io/github/pulls/detail/state/ptrinh/viettelex/133?label=%23133)](https://github.com/ptrinh/viettelex/pull/133) [![#164](https://img.shields.io/github/pulls/detail/state/ptrinh/viettelex/164?label=%23164)](https://github.com/ptrinh/viettelex/pull/164) | Tách âm tiết nối tiếp `V-C-V` sau âm tiết có dấu (`dduowcj+u`); giữ `aa`/`ee` kéo dài sau `ư`/`ơ` (`uwfaaa` → `ừaaa`, `owfaaa` → `ờaaa`). |
| **[UVie](https://github.com/uvie-project/uvie-rs)** · UVie Project ([@uvie-project](https://github.com/uvie-project)) | [![uvie-rs #20](https://img.shields.io/github/pulls/detail/state/uvie-project/uvie-rs/20?label=uvie-rs%20%2320)](https://github.com/uvie-project/uvie-rs/pull/20) [![uvie-mac #25](https://img.shields.io/github/pulls/detail/state/uvie-project/uvie-mac/25?label=uvie-mac%20%2325)](https://github.com/uvie-project/uvie-mac/pull/25) | Xử lý FSM lõi Rust khi nối nguyên âm sau âm tiết đóng (`dduowcj+u`) và đồng bộ vùng đệm `IMKInputController` trên macOS. |
| **[Ngó Sen](https://github.com/ngosen/ngosen)** · Nguyễn Phi ([@nguyenphivn](https://github.com/nguyenphivn)) | [![#764](https://img.shields.io/github/pulls/detail/state/ngosen/ngosen/764?label=%23764)](https://github.com/ngosen/ngosen/pull/764) [![#768](https://img.shields.io/github/pulls/detail/state/ngosen/ngosen/768?label=%23768)](https://github.com/ngosen/ngosen/pull/768) | Hiển thị ngay tiền tố ngoài từ điển trên preedit (`rose`, giữ `khuỷu`); giữ nguyên từ kéo dài khi nhấn `Space` (`uwfaaa` → `ừaaa `, `owfaaa` → `ờaaa `). |
| **[fcitx5-lotus](https://github.com/LotusInputMethod/fcitx5-lotus)** · Nguyễn Hoàng Kỳ ([@nhktmdzhg](https://github.com/nhktmdzhg)) | [![#697](https://img.shields.io/github/pulls/detail/state/LotusInputMethod/fcitx5-lotus/697?label=%23697)](https://github.com/LotusInputMethod/fcitx5-lotus/pull/697) [![#698](https://img.shields.io/github/pulls/detail/state/LotusInputMethod/fcitx5-lotus/698?label=%23698)](https://github.com/LotusInputMethod/fcitx5-lotus/pull/698) | Khôi phục từ phi Việt trước chữ số ở chế độ Macro (`test123`, giữ `k8s`); giữ `a`/`e` kéo dài sau `ư`/`ơ` (`uwfaaa` → `ừaaa`, giữ `owe`/`twee`). |
| **[XKey](https://github.com/xmannv/xkey)** · [@xmannv](https://github.com/xmannv) | [![#338](https://img.shields.io/github/pulls/detail/state/xmannv/xkey/338?label=%23338)](https://github.com/xmannv/xkey/pull/338) | Giữ nguyên âm tiết hoàn chỉnh có móc/trăng khi dư `w` cuối từ và khi xóa lùi (`dduowcjw` → `đượcw`, `⌫` → `được`). |
| **[Vikey](https://github.com/tonyminibot/Vikey)** · [@tonyminibot](https://github.com/tonyminibot) | [![#126](https://img.shields.io/github/pulls/detail/state/tonyminibot/Vikey/126?label=%23126)](https://github.com/tonyminibot/Vikey/pull/126) | Bảo toàn âm tiết móc/trăng khi dư `w` cuối từ và giữ đủ hai chữ `w` khi hoàn nguyên từ tiếng Anh (`awkward`). |
| **Gói HĐH, báo cáo & đặc tả mở** | [Ubuntu LP #2172577](https://bugs.launchpad.net/ubuntu/+source/language-selector/+bug/2172577) · [`typing-modes.yml`](Resources/typing-modes.yml) | Bản vá `.debdiff` đăng ký `im:vi` cho Ubuntu `language-selector`; quy tắc `Bundle ID` macOS (MIT) và báo cáo kỹ thuật ([`phuongtai/ViKey#1`](https://github.com/phuongtai/ViKey/issues/1), [`tr-nam/rustype#1`](https://github.com/tr-nam/rustype/issues/1)). |

## Quyền riêng tư

Engine xử lý nội dung gõ trên thiết bị. Trình cập nhật macOS kết nối GitHub để kiểm tra bản phát hành; biểu mẫu feedback tùy chọn gửi báo cáo tới dịch vụ được cấu hình. Xem [`PRIVACY.md`](PRIVACY.md).

## Giấy phép

Source của dự án trong kho này theo [MIT](LICENSE), trừ thành phần bên thứ ba có thông báo và điều khoản riêng trong [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) và tệp bản quyền Debian. Ứng dụng iOS và Android phân phối riêng, không thuộc kho này và không nằm trong tuyên bố giấy phép trên.

## Liên kết

- [Kiến trúc](docs/ARCHITECTURE.md)
- [Đóng góp ngược dòng](docs/ECOSYSTEM_CONTRIBUTIONS.vi.md)
- [Chính sách quyền riêng tư](PRIVACY.md)
- [Lịch sử phát hành](https://github.com/stevedat/VieLotus-IM/releases)
- [Báo lỗi](https://github.com/stevedat/VieLotus-IM/issues)
