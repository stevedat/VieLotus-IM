# Test status

Updated 2026-11-18. CI evidence: [CI workflow runs (`main`)](https://github.com/stevedat/VieLotus-IM/actions/workflows/ci.yml?query=branch%3Amain). Manual results below are reported by the maintainer; this repository does not contain device logs for those sessions.

## Manual platform tests

| Platform and environment | Result | Test method |
| --- | --- | --- |
| Ubuntu ARM64 | PASS (maintainer-reported) | Manual test in UTM |
| Linux Mint x86_64 | PASS (maintainer-reported) | Manual test; machine/VM detail not recorded |
| Windows 11 ARM64 | PASS (maintainer-reported) | Manual test in UTM |
| Windows 10 (physical PC; architecture not recorded) | PASS (maintainer-reported) | Physical PC |
| macOS 27, Mac mini M2 | PASS (maintainer-reported) | Physical Mac |
| macOS, MacBook Air 2015 Intel | PASS (maintainer-reported) | Physical Mac; macOS version not recorded |
| iOS/iPadOS | [Official App Store release](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799) | The maintainer confirms the released app was tested before publication; device/OS details are not listed here. |
| Android | [Official Google Play release](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard) | The maintainer confirms the released app was tested before publication; device/OS details are not listed here. |

“PASS (maintainer-reported)” records manual results supplied by the project maintainer; it is not a claim that this CI independently reproduced them or that every version/configuration was tested.

## Host apps reported working

The maintainer reports successful Vietnamese typing in these host apps:

- Microsoft Office (Word, Excel, PowerPoint)
- LibreOffice
- macOS Terminal
- NidoOffice
- Firefox, Chrome, Edge, Safari
- Antigravity, Codex/ChatGPT, Kiro, Zalo

The app-to-platform mapping, app versions, OS builds, and test cases were not recorded in the supplied results. This list records reported successful use; it does not imply that every listed app was tested on every platform. The macOS checklist tracks known host coverage separately.

## Continuous integration

| Platform | CI check | Result |
| --- | --- | --- |
| macOS 15 | Swift tests, regression suite, universal app and installer builds | PASS; not a substitute for host-app tests |
| Windows | MSVC C++20 `VieLotusWinEngineLab.exe` runtime suite, TSF x64/ARM64 builds, and installer packaging | PASS in engine lab; CI does not drive live Windows host-app UI |
| Debian `unstable` | `3.0 (quilt)` source/binary build, Lintian gate, standalone `fcitx5-vielotus` / `ibus-vielotus` installs, co-install, `ldd -r`, and purge | PASS |
| Arch Linux | `makepkg`, `pacman -U`, headless KDE Plasma 6 and GNOME Wayland `--activate` / `--doctor` checks | PASS in headless container; not a live compositor typing test |
| Ubuntu 24.04 | Debian package install; IBus/Fcitx5 activation; Telex/VNI and bilingual typing in GTK3 `Gtk.Entry` and Qt5 `QLineEdit` | E2E PASS in test widgets |

## Engine regression results

The CI regression suite reports 9,091/9,091 primary cases (100%), 362/369 symmetric no-context collision cases (98.10%) on Swift and 369/369 (100%) on the C++20 desktop engine, and 179/179 unique Vietnamese paths (100%). These are fixture results, not host-app acceptance results. See [benchmark report](BENCHMARK_REPORT.md).

## Debian status

- `vielotus 2.0.1-1` (sponsored by `byang@debian.org`) was accepted into Debian `unstable` on 2026-11-14: [Debian Package Tracker](https://tracker.debian.org/pkg/vielotus) · [Bug #1152533](https://bugs.debian.org/1152533) · [DFSG review for `vielotus 2.0.1-1`](https://dfsg-new-queue.debian.org/reviews/vielotus/2.0.1-1).
- [`debian/watch`](../CrossPlatform/packaging/debian/watch) (Version 5) tracks upstream GitHub release tags (`v2.0.6` is the latest release tag).
- Upstream and packaging updates for `2.0.6-1` (incorporating the review follow-ups from [Bug #1152533 message #10](https://bugs.debian.org/1152533#10) and enforcing strict opt-in desktop input-method activation and Fcitx5 DefaultIM preservation upstream) are maintained in [`CrossPlatform/packaging/debian/`](../CrossPlatform/packaging/debian) and verified by the `Debian Unstable` CI gate.
