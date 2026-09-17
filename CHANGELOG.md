# Release notes

## 0.3.0 — build 15

### Super Upload

- Paste more than 10 files to queue batches of up to 10. Press Enter once to send the first batch; subsequent batches wait until ChatGPT finishes replying.
- Keep your instruction above the batch progress note and edit it before the first send. Progress notes follow the detected chat language, with Swedish and English support.
- A frosted progress screen prevents accidental chat changes during the upload and includes a Cancel button.
- Files with the same name are kept, using upload-only names such as `report 2.pdf`. Original files remain unchanged, and temporary copies are cleaned up after confirmed batches or when the operation ends.
- Clearly identified failed attachments are skipped and totals are updated. Ambiguous failures stop the queue instead of silently continuing.

### Fixes

- Recognize ChatGPT's current attachment cards, including visible names with numeric suffixes such as `report(1).pdf`.
- Reset batch state correctly between uploads and verify attached files and sent messages before advancing.
- Handle delayed submissions and responses without requiring a second Enter or sending the next batch too early.
- Avoid repeated website microphone permission prompts on the trusted ChatGPT page. macOS microphone permission still applies; camera access remains blocked.

### Installation and compatibility

Download the DMG, open it, and drag ChatPretzel to Applications. This release requires macOS 13 or later and an Apple Silicon Mac. It is ad-hoc signed, not Developer ID signed or notarized. If passkey sign-in does not work in the embedded web view, use password sign-in instead.

Super Upload is intended for regular **Chat**, not Work. ChatGPT's own upload and account limits still apply. Website changes can affect compatibility.

### Verification

56 JavaScript regression tests passed. Local native WebKit tests verified 25-file batching (10 + 10 + 5), delayed replies, edited drafts, and continuation after rejected files. Duplicate-name staging and cleanup were tested locally. The maintainer also confirmed that build 15 worked in a live ChatGPT session. The full XCTest suite was not run because it is unavailable with the selected local toolchain.

ChatPretzel is an independent, unofficial project and is not affiliated with, endorsed by, or sponsored by OpenAI.
