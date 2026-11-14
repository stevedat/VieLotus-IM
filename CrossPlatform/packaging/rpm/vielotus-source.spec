Name:           vielotus
Version:        2.0.3
Release:        1%{?dist}
Summary:        VieLotusIM (Sen Viet) — Next-Gen Vietnamese Input Method for IBus & Fcitx5
License:        MIT AND FSFAP
URL:            https://github.com/stevedat/VieLotus-IM
Source0:        https://github.com/stevedat/VieLotus-IM/archive/refs/tags/v%{version}/vielotus-%{version}.tar.gz

BuildRequires:  cmake >= 3.16
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
BuildRequires:  python3
BuildRequires:  ibus-devel
BuildRequires:  glib2-devel
BuildRequires:  fcitx5-devel

Requires:       ibus-vielotus = %{version}-%{release}
Recommends:     fcitx5-vielotus = %{version}-%{release}

%description
VieLotusIM (Sen Viet) is a modern Vietnamese input method engine supporting
Telex and VNI with Smart Bilingual English-Vietnamese collision resolution,
MacroEngine, Relaxed Coda, Developer Mode backtick code bypass, and per-app
PresentationRules.

%package -n libvielotus0
Summary:        VieLotusIM shared C-ABI core library

%description -n libvielotus0
Pure C++20 Vietnamese input method core engine shared library.

%package -n ibus-vielotus
Summary:        VieLotusIM plugin for IBus
Requires:       libvielotus0 = %{version}-%{release}
Requires:       ibus
Requires:       python3-gobject

%description -n ibus-vielotus
Native IBus engine and GTK3 settings/doctor utility for VieLotusIM (Sen Viet).

%package -n fcitx5-vielotus
Summary:        VieLotusIM plugin for Fcitx5
Requires:       libvielotus0 = %{version}-%{release}
Requires:       fcitx5

%description -n fcitx5-vielotus
Native Fcitx5 addon for VieLotusIM (Sen Viet).

%prep
%autosetup -n VieLotus-IM-%{version}

%build
cmake -S CrossPlatform/capi-native -B build-core \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DCMAKE_INSTALL_LIBDIR=%{_lib} \
    -DVIELOTUS_INSTALL_DEV=ON
cmake --build build-core

cmake -S CrossPlatform/fcitx5-vielotus -B build-fcitx5 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DCMAKE_INSTALL_LIBDIR=%{_lib} \
    -DCMAKE_SKIP_RPATH=ON \
    -DVIELOTUS_LIB_PATH="${PWD}/build-core/libVieLotusCAPI.so" \
    -DVIELOTUS_INCLUDE_DIR="${PWD}/Sources/VieLotusCAPI/include"
cmake --build build-fcitx5

cmake -S CrossPlatform/ibus-vielotus -B build-ibus \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DCMAKE_INSTALL_LIBEXECDIR=lib/ibus \
    -DLIBEXECDIR=%{_prefix}/lib/ibus \
    -DCMAKE_SKIP_RPATH=ON \
    -DVIELOTUS_LIB_PATH="${PWD}/build-core/libVieLotusCAPI.so" \
    -DVIELOTUS_INCLUDE_DIR="${PWD}/Sources/VieLotusCAPI/include"
cmake --build build-ibus

%install
DESTDIR=%{buildroot} cmake --install build-core
DESTDIR=%{buildroot} cmake --install build-fcitx5
DESTDIR=%{buildroot} cmake --install build-ibus

install -Dm644 Resources/typing-modes.yml \
    %{buildroot}%{_datadir}/vielotus/typing-modes.yml
install -Dm644 Resources/typing-modes.yml \
    %{buildroot}%{_datadir}/vielotus/VietLotusIM_VieLotusCore.resources/typing-modes.yml
install -Dm755 CrossPlatform/packaging/linux/vielotus-settings \
    %{buildroot}%{_bindir}/vielotus-settings
ln -sf vielotus-settings %{buildroot}%{_bindir}/vielotus
install -Dm644 CrossPlatform/packaging/linux/vielotus-settings.1 \
    %{buildroot}%{_mandir}/man1/vielotus-settings.1
install -Dm644 CrossPlatform/packaging/linux/vielotus.desktop \
    %{buildroot}%{_datadir}/applications/vielotus.desktop
install -Dm644 CrossPlatform/packaging/linux/org.vielotus.VieLotus.metainfo.xml \
    %{buildroot}%{_datadir}/metainfo/org.vielotus.VieLotus.metainfo.xml

%files
%license LICENSE
%doc README.md

%files -n libvielotus0
%license LICENSE
%{_libdir}/libVieLotusCAPI.so*
%{_includedir}/vielotus.h
%{_datadir}/vielotus/typing-modes.yml
%{_datadir}/vielotus/VietLotusIM_VieLotusCore.resources/typing-modes.yml

%files -n ibus-vielotus
%{_bindir}/vielotus
%{_bindir}/vielotus-settings
%{_mandir}/man1/vielotus-settings.1*
%{_prefix}/lib/ibus/ibus-engine-vielotus
%{_datadir}/ibus/component/vielotus.xml
%{_datadir}/applications/vielotus.desktop
%{_datadir}/metainfo/org.vielotus.VieLotus.metainfo.xml

%files -n fcitx5-vielotus
%{_libdir}/fcitx5/vielotus.so
%{_datadir}/fcitx5/addon/vielotus.conf
%{_datadir}/fcitx5/inputmethod/vielotus-telex.conf
%{_datadir}/fcitx5/inputmethod/vielotus-vni.conf

%changelog
* Sat Nov 14 2026 Trần Phát Đạt (Steve Dat) <ttd1232004@gmail.com> - 2.0.3-1
- Official Pure C++20 source-built release of Sen Việt (VieLotusIM) 2.0.3

* Wed Nov 11 2026 Trần Phát Đạt (Steve Dat) <ttd1232004@gmail.com> - 2.0.2-1
- Official Pure C++20 source-built release of Sen Việt (VieLotusIM) 2.0.2
