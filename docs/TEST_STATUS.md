# Test status

Updated 2026-11-14. CI evidence: [workflow run](https://github.com/stevedat/VieLotus-IM/actions/runs/43533424195). Manual results below are reported by the maintainer; this repository does not contain device logs for those sessions.

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
| Windows | TSF x64/ARM64 builds and installer/MSIX packaging | BUILD PASS; CI skips runtime tests |
| Ubuntu 24.04 | Debian package install; IBus/Fcitx5 activation; Telex/VNI and bilingual typing in GTK3 `Gtk.Entry` and Qt5 `QLineEdit` | E2E PASS in test widgets |

## Engine regression results

The CI regression suite reports 9,091/9,091 primary cases (100%), 365/373 symmetric no-context collision cases (97.86%), and 180/180 unique Vietnamese paths (100%). These are fixture results, not host-app acceptance results. See [benchmark report](BENCHMARK_REPORT.md).

## Debian status

- Upstream tag `v2.0.2` exists, and [`debian/watch`](../CrossPlatform/packaging/debian/watch) tracks GitHub tags.
- The live Debian NEW list shows `vielotus 2.0.1-1`, sponsored by `byang @debian.org`; its DFSG review is accepted. That upload is one upstream version behind this repository's `v2.0.2` tag.
- [DFSG review for `vielotus 2.0.1-1`](https://dfsg-new-queue.debian.org/reviews/vielotus/2.0.1-1) · [Debian NEW queue](https://ftp-master.debian.org/new.html)

The upload is in the review queue, but is not yet listed in the Debian package archive. The upstream tag and watch file are present; a Debian source upload for `2.0.2-1` has not been demonstrated. Check the live queue before describing archive acceptance.
