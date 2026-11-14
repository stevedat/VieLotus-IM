# Privacy

Updated 2026-11-14. This notice covers the source and feedback service included in this repository. It does not describe the separately distributed iOS and Android apps.

## Typing and local data

The input engine processes text locally. Preferences and macros are stored by the host application. The macOS diagnostic logger is debug-only and records event codes, UTF-16 lengths, and range offsets rather than text payloads. Optional Lab tracing requires a user-started session and writes temporary diagnostic events locally.

## Network connections

The macOS updater contacts GitHub Releases when the user opens update settings or requests a check. It downloads an installer only after the user starts an update. GitHub receives the request and ordinary connection metadata.

The website feedback form POSTs submitted reports to `/api/feedback`. The included function can store report type, platform and version details, keys, actual and expected output, target app, message, optional email, and request user-agent in Cloudflare D1. If configured, attachments are stored in Cloudflare R2. Cloudflare Turnstile may be contacted for spam checks. The repository does not define a retention period or deletion process.

The macOS app does not send feedback in the background. When the user chooses a feedback action, report text can include keys and outputs, app/version/OS details, input method settings, macro count, and app overrides. GitHub and email drafts may contain report text in the URL. The app also copies the report to the clipboard; Zalo/email actions open external apps or services. Review the preview and remove sensitive details first.

## Scope

This notice describes checked-in source. It does not verify every installer, operating system, host application, or separately distributed mobile app. See [third-party notices](docs/THIRD_PARTY_NOTICES.md).

Report discrepancies through [GitHub Issues](https://github.com/stevedat/VieLotus-IM/issues).
