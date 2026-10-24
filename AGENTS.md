# AGENTS.md — VietLotusIM (Sen Việt) [Open-Core Edition]

## Build & Verification Commands

```bash
swift build --product VieLotusIM           # Compile macOS IMK shell against VieLotusCore.xcframework
./scripts/build_imk.sh                     # Build release universal VieLotusIM.app + codesign
./scripts/build_pkg.sh                     # Build auto-registering installer package (VieLotusIM.pkg)
shasum -a 256 -c Binaries/checksums.sha256 # Verify cryptographic integrity of prebuilt binaries
```

## Open-Core Architecture

VietLotusIM follows an **Open-Core** model designed for full OS-boundary transparency and security auditability while protecting core linguistic engine IP:

- **`Sources/VieLotusIM/` (Public — MIT)**: Pure Apple `InputMethodKit` shell (`IMKInputController`, `IMKServer`, `IMKTextInput`). Zero `CGEventTap`, zero `CGEventSource`, zero Accessibility permissions, zero keystroke logging.
- **`Sources/VieLotusTrace/` (Public — MIT)**: Sanitized diagnostic trace contracts.
- **`Sources/VieLotusCAPI/include/vielotus.h` (Public — MIT)**: Zero-copy C-ABI header for desktop platform shells.
- **`CrossPlatform/` (Public — MIT)**: Native desktop input method shells for Windows (`windows-tsf`) and Linux (`fcitx5-vielotus`, `ibus-vielotus`).
- **`Resources/typing-modes.yml` (Public — MIT)**: Data-driven per-app presentation rules.
- **`docs/ARCHITECTURE.md` & `docs/BENCHMARK_REPORT.md` (Public)**: High-level system architecture and regression matrix disclosure (**100.00% (9,091 / 9,091)** overall alongside symmetric collision survival `vn_survives_collision` / `ambiguous_both_sides` **97.33% (365 / 375)** and `whitelist_safe = never` **100.00% (182 / 182)**).
- **`Frameworks/VieLotusCore.xcframework` & `Binaries/` (Public Prebuilt Binary)**: Universal binaries (`arm64` + `x86_64`) enabling anyone to compile `VieLotusIM.app` from source and verify SHA-256 integrity.
