# VietLotusIM repository notes

## Scope

This public repository contains the Swift engine and macOS InputMethodKit app, plus the C++20 Windows and Linux engines/adapters. The iOS and Android application source is maintained outside this repository.

Project-owned source in this repository is MIT licensed. Keep third-party notices with their corresponding files and packages. Do not add mobile application source, signing credentials, build outputs, or private product integrations to the public export.

## Build and verify

Run on macOS 13 or later with the Swift 6 toolchain:

```sh
swift test
swift run VieLotusCLI --benchmark
swift build --product VieLotusIM
```

The Swift package compiles `Sources/VieLotusCore` from source. It does not fetch a prebuilt core binary.

Linux and Windows build steps are maintained under `CrossPlatform/` and `scripts/`.

## Release rules

GitHub Releases contain only downloadable installers and `checksums.sha256`. Do not upload core framework archives, source packages, APT metadata, or build products. The release workflow verifies the installer allowlist and checksum manifest.

Benchmark notes must report the primary suite together with `ambiguous_both_sides` and the single-path `whitelist_safe = never` result. Include the suite conditions and measurement date.
