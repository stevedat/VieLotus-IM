# VieLotusIM (Sen Việt)

Vietnamese input methods for macOS, Windows, and Linux.

This repository contains the Swift engine and macOS InputMethodKit shell, plus the C++20 Windows and Linux engines and adapters. iOS and Android applications are distributed separately; their application source is not in this repository.

## Platforms

| Platform | Source in this repository | Downloads |
| --- | --- | --- |
| macOS | Swift engine and InputMethodKit shell | [Latest release](https://github.com/stevedat/VieLotus-IM/releases/latest) |
| Windows | C++20 engine and TSF shell | [Latest release](https://github.com/stevedat/VieLotus-IM/releases/latest) · [Microsoft Store](https://apps.microsoft.com/detail/9PF5K64GXXSH) |
| Linux | C++20 engine, IBus/Fcitx5 adapters, Debian packaging | [Launchpad PPA](https://launchpad.net/~stevedat/+archive/ubuntu/vielotus) · [Latest release](https://github.com/stevedat/VieLotus-IM/releases/latest) |
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

## Benchmark snapshot

Measured on 2026-11-14 from the source snapshot published with this README using `swift run VieLotusCLI --benchmark --json`:

| Metric | Result |
| --- | ---: |
| Primary suite | 9,091 / 9,091 (100.00%) |
| Symmetric no-context collisions | 365 / 373 (97.86%) |
| Unique Vietnamese paths (`whitelist_safe = never`) | 180 / 180 (100.00%) |

These are regression-suite results, not a claim of error-free typing in every application or device. See [`docs/BENCHMARK_REPORT.md`](docs/BENCHMARK_REPORT.md) for the test conditions.

## Privacy

Typing is processed locally by the input engine. The macOS updater contacts GitHub for release checks; the optional website feedback form sends submitted reports to its configured service. See [`PRIVACY.md`](PRIVACY.md).

## License

Project source in this repository is licensed under [MIT](LICENSE), except third-party materials whose notices and terms are listed in [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) and the Debian copyright file. The separately distributed iOS and Android applications are outside this repository and are not covered by this license statement.

## Links

- [Architecture](docs/ARCHITECTURE.md)
- [Privacy policy](PRIVACY.md)
- [Release history](https://github.com/stevedat/VieLotus-IM/releases)
- [Issues](https://github.com/stevedat/VieLotus-IM/issues)
