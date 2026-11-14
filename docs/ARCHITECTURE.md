# Architecture

## Swift engine and macOS app

`Sources/VieLotusCore` contains the Swift input engine, composition state, bilingual handling, spelling abstractions, preferences, and supporting utilities. The source is included in this repository and built by SwiftPM.

`Sources/VieLotusIM` is the macOS app. It integrates with text clients through Apple's InputMethodKit APIs. It does not use a global event tap or request Accessibility access for normal typing.

`Sources/VieLotusTrace` contains diagnostic event and trace storage code. Diagnostic recording is separate from normal typing and must be explicitly started by the user.

## Windows and Linux

`Sources/VieLotusCoreWindows` contains the C++20 engine and its source lexicon/generator. `CrossPlatform/windows-tsf` provides the Windows TSF adapter. `CrossPlatform/ibus-vielotus` and `CrossPlatform/fcitx5-vielotus` provide Linux adapters over the C API.

Debian packaging definitions are in `CrossPlatform/packaging/debian`. The Debian source package uses the source files named in its `copyright` file and builds the engine and adapters from source.

## Mobile apps

The iOS and Android applications are distributed separately. Their application source and build projects are not in this repository. The Swift core includes platform abstractions, but this repository does not build or ship the iOS app.

## Build graph

```text
SwiftPM
  VieLotusCore ── VieLotusIM (macOS InputMethodKit)
       ├───────── VieLotusCLI (regression benchmark)
       └───────── VieLotusCoreTests

C++20
  VieLotusCoreWindows ── C API ── IBus / Fcitx5 / Windows TSF
```

All project-owned source in this repository is licensed under MIT. Third-party materials retain the terms in their notices.
