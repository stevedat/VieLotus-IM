# VieLotusIM (Sen Việt)

Vietnamese input methods for macOS, Windows, and Linux.

This repository contains the Swift engine and macOS InputMethodKit shell, plus the C++20 Windows and Linux engines and adapters. iOS and Android applications are distributed separately; their application source is not in this repository.

## Platforms

| Platform | Source in this repository | Downloads |
| --- | --- | --- |
| macOS | Swift engine and InputMethodKit shell | [Latest release](https://github.com/stevedat/VieLotus-IM/releases/latest) |
| Windows | C++20 engine and TSF shell | [Latest release](https://github.com/stevedat/VieLotus-IM/releases/latest) · [Microsoft Store](https://apps.microsoft.com/detail/9PF5K64GXXSH) |
| Linux | C++20 engine, IBus/Fcitx5 adapters, Debian packaging | [Install on Ubuntu/Debian/Arch](docs/INSTALL_LINUX.md) · [Latest release](https://github.com/stevedat/VieLotus-IM/releases/latest) |
| iOS/iPadOS | App source is not included | [App Store](https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799) |
| Android | App source is not included | [Google Play](https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard) |

## Build and verify

Requirements: macOS 13 or later and the Swift 6 toolchain.

```sh
swift test
swift run VieLotusCLI --benchmark
swift build --product VieLotusIM
./scripts/build_imk.sh
```

The Swift package uses Swift 5 language mode for source compatibility. The engine source and its tests are included; SwiftPM does not download a proprietary engine binary.

Linux and Windows build instructions are in [`CrossPlatform`](CrossPlatform/). Debian packaging files are in [`CrossPlatform/packaging/debian`](CrossPlatform/packaging/debian/).

## Test status

CI verifies Linux IBus/Fcitx5 typing in GTK3 and Qt5 test widgets. The maintainer also reports manual tests on macOS, Windows, Ubuntu ARM64, and Linux Mint, and successful typing in several host apps. iOS and Android are available in their official stores. See the [platform test status](docs/TEST_STATUS.md) for scope and evidence type, and the [macOS field-test checklist](docs/FIELD_TEST_CHECKLIST.md).

## Benchmark snapshot

Measured on 2026-11-14 from the source snapshot published with this README using `swift run VieLotusCLI --benchmark --json`:

| Metric | Result |
| --- | ---: |
| Primary suite | 9,091 / 9,091 (100.00%) |
| Symmetric no-context collisions | 365 / 373 (97.86%) |
| Unique Vietnamese paths (`whitelist_safe = never`) | 180 / 180 (100.00%) |

These are regression-suite results, not a claim of error-free typing in every application or device. See [`docs/BENCHMARK_REPORT.md`](docs/BENCHMARK_REPORT.md) for the test conditions.

## Upstream contributions

Patches, unit tests, and packaging contributions submitted to peer open-source projects (full ledger in [`docs/ECOSYSTEM_CONTRIBUTIONS.md`](docs/ECOSYSTEM_CONTRIBUTIONS.md)):

| Project & Maintainer | PRs & Live Status | Contributed Fix / Scope |
| :--- | :--- | :--- |
| **[VietTelex](https://github.com/ptrinh/viettelex)** · Phil Trịnh ([@ptrinh](https://github.com/ptrinh)) | [![#133](https://img.shields.io/github/pulls/detail/state/ptrinh/viettelex/133?label=%23133)](https://github.com/ptrinh/viettelex/pull/133) [![#164](https://img.shields.io/github/pulls/detail/state/ptrinh/viettelex/164?label=%23164)](https://github.com/ptrinh/viettelex/pull/164) | Post-toned `V-C-V` syllable splitting (`dduowcj+u`); preserve literal `aa`/`ee` elongation after `ư`/`ơ` (`uwfaaa` → `ừaaa`, `owfaaa` → `ờaaa`). |
| **[UVie](https://github.com/uvie-project/uvie-rs)** · UVie Project ([@uvie-project](https://github.com/uvie-project)) | [![uvie-rs #20](https://img.shields.io/github/pulls/detail/state/uvie-project/uvie-rs/20?label=uvie-rs%20%2320)](https://github.com/uvie-project/uvie-rs/pull/20) [![uvie-mac #25](https://img.shields.io/github/pulls/detail/state/uvie-project/uvie-mac/25?label=uvie-mac%20%2325)](https://github.com/uvie-project/uvie-mac/pull/25) | Rust FSM post-toned closed-syllable continuation (`dduowcj+u`) and macOS `IMKInputController` multi-syllable buffer sync. |
| **[Ngó Sen](https://github.com/ngosen/ngosen)** · Nguyễn Phi ([@nguyenphivn](https://github.com/nguyenphivn)) | [![#764](https://img.shields.io/github/pulls/detail/state/ngosen/ngosen/764?label=%23764)](https://github.com/ngosen/ngosen/pull/764) [![#768](https://img.shields.io/github/pulls/detail/state/ngosen/ngosen/768?label=%23768)](https://github.com/ngosen/ngosen/pull/768) | Show non-dictionary prefixes immediately in preedit (`rose`, keeping `khuỷu`); keep stretched words on `Space` (`uwfaaa` → `ừaaa `, `owfaaa` → `ờaaa `). |
| **[fcitx5-lotus](https://github.com/LotusInputMethod/fcitx5-lotus)** · Nguyễn Hoàng Kỳ ([@nhktmdzhg](https://github.com/nhktmdzhg)) | [![#697](https://img.shields.io/github/pulls/detail/state/LotusInputMethod/fcitx5-lotus/697?label=%23697)](https://github.com/LotusInputMethod/fcitx5-lotus/pull/697) [![#698](https://img.shields.io/github/pulls/detail/state/LotusInputMethod/fcitx5-lotus/698?label=%23698)](https://github.com/LotusInputMethod/fcitx5-lotus/pull/698) | Restore non-Vietnamese words before digits in Macro mode (`test123`, keeping `k8s`); preserve `a`/`e` elongation after `ư`/`ơ` (`uwfaaa` → `ừaaa`, keeping `owe`/`twee`). |
| **[XKey](https://github.com/xmannv/xkey)** · [@xmannv](https://github.com/xmannv) | [![#338](https://img.shields.io/github/pulls/detail/state/xmannv/xkey/338?label=%23338)](https://github.com/xmannv/xkey/pull/338) | Keep completed horn/breve syllables intact on trailing `w` and Backspace (`dduowcjw` → `đượcw`, `⌫` → `được`). |
| **[Vikey](https://github.com/tonyminibot/Vikey)** · [@tonyminibot](https://github.com/tonyminibot) | [![#126](https://img.shields.io/github/pulls/detail/state/tonyminibot/Vikey/126?label=%23126)](https://github.com/tonyminibot/Vikey/pull/126) | Preserve completed horn/breve syllables on trailing `w` and retain both `w` keys on English restore (`awkward`). |
| **OS packaging, reports & open spec** | [Ubuntu LP #2172577](https://bugs.launchpad.net/ubuntu/+source/language-selector/+bug/2172577) · [`typing-modes.yml`](Resources/typing-modes.yml) | `.debdiff` registering `im:vi` in Ubuntu `language-selector`; MIT macOS `Bundle ID` compatibility rules and technical reports ([`phuongtai/ViKey#1`](https://github.com/phuongtai/ViKey/issues/1), [`tr-nam/rustype#1`](https://github.com/tr-nam/rustype/issues/1)). |

## Privacy

Typing is processed locally by the input engine. The macOS updater contacts GitHub for release checks; the optional website feedback form sends submitted reports to its configured service. See [`PRIVACY.md`](PRIVACY.md).

## License

Project source in this repository is licensed under [MIT](LICENSE), except third-party materials whose notices and terms are listed in [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) and the Debian copyright file. The separately distributed iOS and Android applications are outside this repository and are not covered by this license statement.

## Links

- [Architecture](docs/ARCHITECTURE.md)
- [Upstream contributions](docs/ECOSYSTEM_CONTRIBUTIONS.md)
- [Privacy policy](PRIVACY.md)
- [Release history](https://github.com/stevedat/VieLotus-IM/releases)
- [Issues](https://github.com/stevedat/VieLotus-IM/issues)
