# macOS host application field test checklist

Maintainer-reported manual test coverage is summarized in [test status](TEST_STATUS.md). This checklist is for capturing reproducible details not yet recorded (app version, OS build, and scenarios); CI fixtures do not count as host verification.

| Host | OS version | Scenario | Result | Notes |
| --- | --- | --- | --- | --- |
| TextEdit |  | Vietnamese Telex/VNI, backspace, selection replacement | NOT RECORDED |  |
| Safari | OS build not recorded | Address field and web form | PASS (maintainer-reported) | Details not recorded |
| Chromium-based apps | OS/app mapping not recorded | Composition, commit, caret movement | PASS (maintainer-reported) | Chrome, Edge; details not recorded |
| Terminal.app | macOS build not recorded | Command line, completion, backspace | PASS (maintainer-reported) | Details not recorded |
| Office apps | OS/app mapping not recorded | Cell/document editing and undo | PASS (maintainer-reported) | Microsoft Office, LibreOffice; details not recorded |

Record app version, OS version, input method settings, and reproducible steps when available. A maintainer-reported result does not establish coverage for other app or OS versions.
