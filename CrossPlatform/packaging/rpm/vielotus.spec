Name:           vielotus
Version:        2.0.0
Release:        1%{?dist}
Summary:        Sen Việt (VieLotusIM) - Bộ gõ tiếng Việt thế hệ mới cho Linux (IBus & Fcitx5)

License:        MIT
URL:            https://github.com/stevedat/VieLotus-IM
Packager:       Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM>
ExclusiveArch:  x86_64 aarch64

Requires:       glibc
Requires:       glib2
Requires:       python3
Requires:       python3-gobject
Recommends:     ibus
Recommends:     fcitx5
Provides:       fcitx5-vielotus = %{version}-%{release}
Provides:       ibus-vielotus = %{version}-%{release}

%description
VieLotusIM (Sen Việt) là bộ gõ tiếng Việt thế hệ mới, xây dựng trên lõi Pure Swift 6
kết hợp C-ABI đạt độ chính xác song ngữ 100.00% (với 97.33% đối xứng hai chiều).
Hỗ trợ đồng thời cả IBus và Fcitx5 trên Fedora, RHEL, CentOS Stream và openSUSE.

%install
%ifarch aarch64
DEB_ARCH="arm64"
%else
DEB_ARCH="amd64"
%endif

DEB_FILE="%{_topdir}/SOURCES/vielotus_%{version}_${DEB_ARCH}.deb"
if [ ! -f "${DEB_FILE}" ] && [ -f "Binaries/linux/vielotus_%{version}_${DEB_ARCH}.deb" ]; then
    DEB_FILE="Binaries/linux/vielotus_%{version}_${DEB_ARCH}.deb"
fi

mkdir -p "%{_builddir}/deb_extract"
(cd "%{_builddir}/deb_extract" && ar x "${DEB_FILE}" && tar -xf data.tar.* -C "%{buildroot}")

mkdir -p "%{buildroot}%{_libdir}/fcitx5"
if [ "%{_libdir}" != "/usr/lib" ]; then
    ln -sf /usr/lib/libVieLotusCAPI.so "%{buildroot}%{_libdir}/libVieLotusCAPI.so"
    ln -sf /usr/lib/fcitx5/vielotus.so "%{buildroot}%{_libdir}/fcitx5/vielotus.so"
fi

%post
/sbin/ldconfig || :
if command -v ibus >/dev/null 2>&1; then
    ibus write-cache --system >/dev/null 2>&1 || :
fi

%postun
/sbin/ldconfig || :

%files
/etc/ld.so.conf.d/vielotus.conf
/usr/bin/vielotus
/usr/bin/vielotus-settings
/usr/include/vielotus.h
/usr/lib/libVieLotusCAPI.so
/usr/lib/vielotus/*
/usr/lib/fcitx5/vielotus.so
/usr/lib/*-linux-gnu/fcitx5/vielotus.so
/usr/lib/ibus/ibus-engine-vielotus
%if "%{_libdir}" != "/usr/lib"
%{_libdir}/libVieLotusCAPI.so
%{_libdir}/fcitx5/vielotus.so
%endif
/usr/share/applications/vielotus.desktop
/usr/share/doc/vielotus/README.md
/usr/share/fcitx5/addon/vielotus.conf
/usr/share/fcitx5/inputmethod/vielotus-telex.conf
/usr/share/fcitx5/inputmethod/vielotus-vni.conf
/usr/share/ibus/component/vielotus.xml
/usr/share/icons/hicolor/*/apps/vielotus.png
/usr/share/metainfo/org.vielotus.VieLotus.metainfo.xml
/usr/share/vielotus/*

%changelog
* Thu Oct 29 2026 Trần Phát Đạt (Steve Dat) <https://github.com/stevedat/VieLotus-IM> - 2.0.0-1
- Release of VieLotusIM (Sen Việt) v2.0.0 All-in-One (IBus & Fcitx5) for Linux (x86_64 & aarch64)
