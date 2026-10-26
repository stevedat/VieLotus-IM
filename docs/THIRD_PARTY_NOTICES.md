# Third-Party Notices & Open Source Acknowledgments

VieLotusIM (Sen Việt) is licensed under the [MIT License](../LICENSE). 

In the spirit of open-source collaboration and engineering excellence, VieLotusIM respects, learns from, and acknowledges foundational research, tools, and prior art in the Vietnamese macOS input method ecosystem:

---

## 1. Algorithmic & Linguistic Foundations

- **UniKey**: Open-source core algorithms by **Phạm Kim Long** (GPL).
  - *Reference*: Foundational state-machine principles for Vietnamese syllable orthography and diacritic placement rules.
- **OpenKey**: Created by **Mai Vũ Tuyên** ([tuyenvm/OpenKey](https://github.com/tuyenvm/OpenKey), GNU GPLv3).
  - *Reference*: Structural reference for legacy codepage mappings (TCVN3 / ABC, VNI Windows, Unicode Compound) and phonetic spell-checking matrices.
- **Bamboo Engine**: Created by **Lương Thanh Lam** ([BambooEngine/bamboo-core](https://github.com/BambooEngine/bamboo-core), GNU GPLv3).
  - *Reference*: Syllable structure heuristics and forward-deletion disambiguation logic.

---

## 2. InputMethodKit & Native macOS Engineering

- **VietTelex**: Engineered by **Phil Trịnh** ([ptrinh/viettelex](https://github.com/ptrinh/viettelex), MIT License).
  - *Reference & Upstream Contribution*: Extensive technical research and edge-case documentation regarding Apple `InputMethodKit` runtime behaviors (`docs/MACOS_IME_NOTES.md`), secure input detection (`AXSecureTextField`), regression benchmark suite structure (`telex_test_suite.csv`, 9,091 test cases), and upstream collaboration ([ptrinh/viettelex#133](https://github.com/ptrinh/viettelex/pull/133)).
- **UVie**: Developed by **UVie Project** ([uvie-project/uvie-rs](https://github.com/uvie-project/uvie-rs), [uvie-project/uvie-mac](https://github.com/uvie-project/uvie-mac), MIT License).
  - *Reference & Upstream Contribution*: Rust-based Vietnamese Telex/VNI engine and native macOS InputMethodKit shell; upstream regression test suites and root-cause analysis for post-toned syllable state synchronization and V-C-V splitting ([uvie-project/uvie-rs#20](https://github.com/uvie-project/uvie-rs/pull/20), [uvie-project/uvie-mac#25](https://github.com/uvie-project/uvie-mac/pull/25)).
- **XKey**: Developed by **xmannv** ([xmannv/xkey](https://github.com/xmannv/xkey), MIT License).
  - *Reference*: Real-time keystroke debugging concepts and multi-mode switching paradigms.
- **PHTV**: Created by **Phạm Hùng Tiến** ([PhamHungTien/PHTV](https://github.com/PhamHungTien/PHTV), GNU AGPLv3).
  - *Reference (Clean-room conceptual)*: Engineering discipline, compatibility matrix edge-case documentation (TeXstudio single-unit buffering, JetBrains, Claude Code CLI timings), and technical debt governance policies.

---

## 3. Apple System Frameworks

- **Frameworks**: `InputMethodKit.framework`, `Carbon.framework`, `NaturalLanguage.framework`, `AppKit.framework`.
- **Copyright**: © Apple Inc. All rights reserved.
- **Purpose**: Native system frameworks utilized for secure, non-invasive input method integration without `CGEventTap` or Accessibility permission requirements.

