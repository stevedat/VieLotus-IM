# Test status

Status checked 2026-11-14. [CI run](https://github.com/stevedat/VieLotus-IM/actions/runs/43533424195).

| Platform | What was checked | Result |
| --- | --- | --- |
| macOS 15 CI | Swift tests, regression suite, universal app and installer builds | PASS. Typing in named macOS apps has not been field-tested; see [checklist](FIELD_TEST_CHECKLIST.md). |
| Windows CI | TSF x64/ARM64 builds and installer/MSIX packaging | BUILD PASS. CI skips runtime tests; typing in Windows host apps is not verified. |
| Ubuntu 24.04 CI | Debian package install; IBus and Fcitx5 activation; Telex/VNI and bilingual typing in GTK3 `Gtk.Entry` and Qt5 `QLineEdit` | E2E PASS. This verifies those test widgets, not every desktop or app. |
| Debian archive | `vielotus 2.0.1-1` is listed in NEW; its DFSG review is accepted | Review accepted; archive inclusion is pending. This does not verify runtime typing on Debian. |
| iOS/iPadOS | App source and device test results are outside this repository | NOT VERIFIED here. |
| Android | App source and device test results are outside this repository | NOT VERIFIED here. |

## Engine regression results

The macOS CI regression suite reports 9,091/9,091 primary cases (100%), 365/373 symmetric no-context collision cases (97.86%), and 180/180 unique Vietnamese paths (100%). These are fixture results, not host-app acceptance results. See [benchmark report](BENCHMARK_REPORT.md).

## Debian status links

- Upstream tag `v2.0.2` exists, and [`debian/watch`](../CrossPlatform/packaging/debian/watch) tracks GitHub tags.
- The live Debian NEW list shows `vielotus 2.0.1-1`, sponsored by `byang @debian.org`; its DFSG review is accepted. That upload is one upstream version behind this repository's `v2.0.2` tag.
- [DFSG review for `vielotus 2.0.1-1`](https://dfsg-new-queue.debian.org/reviews/vielotus/2.0.1-1)
- [Debian NEW queue](https://ftp-master.debian.org/new.html)

The upload is in the review queue, but is not yet listed in the Debian package archive. The upstream tag and watch file are present; a Debian source upload for `2.0.2-1` has not been demonstrated. Check the live queue before describing archive acceptance.
