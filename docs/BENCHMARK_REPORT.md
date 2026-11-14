# Regression benchmark

**Measured:** 14 November 2026
**Command:** `swift run VieLotusCLI --benchmark --json`
**Build:** SwiftPM debug configuration on an Apple Silicon Mac. The command measures the engine test harness, not a physical keyboard or host application.

## Results

| Metric | Result |
| --- | ---: |
| Primary regression suite | 9,091 / 9,091 (100.00%) |
| Symmetric no-context collisions (`ambiguous_both_sides`) | 365 / 373 (97.86%) |
| Vietnamese unique paths (`whitelist_safe = never`) | 180 / 180 (100.00%) |

The primary suite contains transformations, English preservation, modifier cancellation, raw-word restoration, and ambiguous words driven with English context. The symmetric metric replays collision words without context; it measures the English/Vietnamese tradeoff that the primary result does not cover.

The reported results are from the source snapshot that produced this report. Re-run the command after changing the engine. A passing synthetic suite does not establish latency or correctness on every device, OS version, or text client.

## Run it

```sh
swift run VieLotusCLI --benchmark
swift run VieLotusCLI --benchmark --json
```

The suite data is in `Sources/VieLotusCLI/Resources/test_suite.csv`. Tests and the CLI harness are included in the repository.
