# Cài đặt trên Linux

Chọn một cách cài. Tệp tải nằm trong [bản phát hành GitHub mới nhất](https://github.com/stevedat/VieLotus-IM/releases/latest).

## Trình cài đặt tự động

Trình cài đặt chính thức nhận diện package manager và kiến trúc CPU, cài gói cần thiết rồi chọn gói cài hoặc biên dịch phù hợp:

```sh
curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
```

## Ubuntu: PPA

Dùng PPA nếu phiên bản Ubuntu và kiến trúc máy có trong [Launchpad](https://launchpad.net/~stevedat/+archive/ubuntu/vielotus):

```sh
sudo add-apt-repository ppa:stevedat/vielotus
sudo apt update
sudo apt install vielotus
```

## Debian, Ubuntu, Mint: gói `.deb`

Tải đúng gói `vielotus_<version>_<arch>.deb` từ bản phát hành mới nhất (`amd64` cho x86_64, `arm64` cho ARM64), rồi cài bằng APT. Thay giá trị bên dưới theo phiên bản và kiến trúc của tệp đã tải:

```sh
version=2.0.3
arch=amd64 # dùng arm64 cho máy ARM64
sudo apt install "./vielotus_${version}_${arch}.deb"
```

APT tự xử lý các gói phụ thuộc. Bản phát hành có `checksums.sha256` để kiểm tra tệp tải xuống.

## Arch Linux và Arch ARM

`CrossPlatform/packaging/arch/PKGBUILD` biên dịch lõi C++20, plugin Fcitx5 và engine IBus bản địa theo đúng thư viện hệ thống Arch (`PKGBUILD.bin` cũng được cung cấp nếu muốn đóng gói lại từ `.deb`):

```sh
sudo pacman -S --needed base-devel cmake extra-cmake-modules git
# Kèm ít nhất một bộ khung nhập liệu:
sudo pacman -S --needed fcitx5-im  # Fcitx5, gồm frontend GTK/Qt (KDE/Hyprland/XFCE)
# hoặc
sudo pacman -S --needed ibus       # IBus (GNOME)

git clone --depth 1 https://github.com/stevedat/VieLotus-IM.git
cd VieLotus-IM/CrossPlatform/packaging/arch
makepkg -si
vielotus-settings --activate
```

## Khởi chạy và thêm bộ gõ

Gói cài đặt có tác vụ thiết lập ở lần đăng nhập đầu. Trong phiên desktop được hỗ trợ, tác vụ làm mới danh sách bộ gõ và thử thêm/kích hoạt Sen Việt. Trình cài đặt tự động cũng thêm Sen Việt vào danh sách gói của Ubuntu Language Selector trên Ubuntu được hỗ trợ; cài `.deb` trực tiếp không thay đổi danh sách Language Selector này.

Trên Ubuntu/GNOME, nhấn `Super` + `Space` rồi chọn **Sen Việt – Telex** (hoặc VNI). Trên desktop khác, dùng phím tắt và phần cài đặt bộ gõ của desktop đó. Nếu chưa thấy Sen Việt, chạy:

```sh
vielotus-settings --activate
```

Sau đó kiểm tra mục bàn phím/ngôn ngữ nhập liệu trong cài đặt desktop. Trên Ubuntu/GNOME Wayland, đăng xuất rồi đăng nhập lại một lần nếu bộ gõ chưa xuất hiện hoặc chỉ hiện tên `vielotus`. Arch và desktop không dùng Debian không có mục đăng ký Ubuntu Language Selector; cách hiển thị bộ gõ tùy desktop và IBus/Fcitx5 đang hoạt động.

Chẩn đoán bằng `vielotus-settings --doctor`. Xem [trạng thái kiểm thử Linux](TEST_STATUS.md).
