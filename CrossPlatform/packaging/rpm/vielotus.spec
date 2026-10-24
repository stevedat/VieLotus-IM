Name:           vielotus
Version:        1.1.1
Release:        1%{?dist}
Summary:        Sen Việt (VieLotusIM) - Bộ gõ tiếng Việt thế hệ mới cho Linux

License:        MIT
URL:            https://github.com/vietlotus/vielotus
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  fcitx5-devel
BuildRequires:  ibus-devel
BuildRequires:  glib2-devel

Requires:       fcitx5

%description
VieLotusIM (Sen Việt) là bộ gõ tiếng Việt thế hệ mới, xây dựng trên lõi Pure Swift 6
kết hợp C-ABI đạt độ chính xác song ngữ 99.97%. Hỗ trợ cả Fcitx5 và IBus trên Linux.

%package -n fcitx5-vielotus
Summary:        Fcitx5 engine for VieLotusIM (Sen Việt)
Requires:       fcitx5
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description -n fcitx5-vielotus
Fcitx5 input method engine plugin for VieLotusIM (Sen Việt).

%package -n ibus-vielotus
Summary:        IBus engine for VieLotusIM (Sen Việt)
Requires:       ibus
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description -n ibus-vielotus
IBus input method engine plugin for VieLotusIM (Sen Việt).

%prep
%autosetup

%build
# 1. Swift Core C-ABI library
swift build -c release --product VieLotusCAPI

# 2. Fcitx5 Addon
%cmake -B build-fcitx5 -S CrossPlatform/fcitx5-vielotus
%cmake_build -B build-fcitx5

# 3. IBus Engine
%cmake -B build-ibus -S CrossPlatform/ibus-vielotus
%cmake_build -B build-ibus

%install
# Install Fcitx5
%cmake_install -B build-fcitx5

# Install IBus
%cmake_install -B build-ibus

# Install Shared library
install -D -m 0755 .build/release/libVieLotusCAPI.so %{buildroot}%{_libdir}/libVieLotusCAPI.so
install -D -m 0644 Sources/VieLotusCAPI/include/vielotus.h %{buildroot}%{_includedir}/vielotus.h

# Install Freedesktop hicolor icons
for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
    if [ -f "CrossPlatform/linux-icons/hicolor_${size}_apps/vielotus.png" ]; then
        install -D -m 0644 "CrossPlatform/linux-icons/hicolor_${size}_apps/vielotus.png" \
            "%{buildroot}%{_datadir}/icons/hicolor/${size}/apps/vielotus.png"
    fi
done

%files
%license LICENSE
%{_libdir}/libVieLotusCAPI.so
%{_includedir}/vielotus.h
%{_datadir}/icons/hicolor/*/apps/vielotus.png

%files -n fcitx5-vielotus
%{_libdir}/fcitx5/vielotus.so
%{_datadir}/fcitx5/addon/vielotus.conf

%files -n ibus-vielotus
%{_libexecdir}/ibus-engine-vielotus
%{_datadir}/ibus/component/vielotus.xml

%changelog
* Mon Oct 13 2026 VieLotusIM Team <dev@vielotus.org> - 1.1.1-1
- Release of VieLotusIM (Sen Việt) v1.1.1 for Linux
