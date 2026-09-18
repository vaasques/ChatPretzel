# Release notes

## 0.3.5 — Live gallery verification fix

### Fixed

- Recognise the real sent-image gallery used by ChatGPT, where one generic attachment wrapper contains separate interactive image controls.
- Continue Super Upload when ChatGPT changes a filename suffix between the composer and the sent message, for example from `image(2).png` to `image(3).png`.
- Match those website-generated aliases one-to-one against the original batch while keeping genuine numbered filenames and duplicate files distinct.
- Include content-free live control, image and wrapper counts in a stopped-upload error so a future ChatGPT layout change can be diagnosed without exposing chat text or filenames.

### Verification

- 90 JavaScript adapter regression tests passed, including a ten-image reproduction of the live gallery structure and alias transition that previously produced 0 of 10 verified files.
- The native AppKit/WebKit harness advanced a 1,500-file selection from batch 1 to batch 2 and completed the 25-file 10 + 10 + 5 flow, delayed final reply, cancellation and background response without action controls.
- The full XCTest suite remains unavailable with the selected local Command Line Tools because XCTest is not included.

This is a local reliability update. ChatGPT service limits and future website changes can still affect very large uploads.

## 0.3.4 — Super Upload transition fix

### Fixed

- Continue from the first 10 files when ChatGPT keeps an older assistant node while rendering the new completed answer in a different turn shape.
- Bind role-less transition layouts to the exact submitted user message and exact attachment set without accepting stale or assistant-authored lookalikes.
- Read sent galleries from the complete conversation turn, including image filenames exposed only through image metadata.
- Stop safely if WebKit does not return an operation result, without treating an uncertain send as proof that nothing was sent.

### Verification

- 85 JavaScript adapter regression tests passed.
- A native AppKit/WebKit regression with a 1,500-file selection advanced automatically from files 1–10 to files 11–20 under the reproduced transition layout.
- Native AppKit/WebKit regressions passed for the complete 25-file 10 + 10 + 5 flow with the window hidden, delayed final reply, cancellation, No sending nothing, and replies without action controls.
- The full XCTest suite remains unavailable with the selected local Command Line Tools because XCTest is not included.

This is a local reliability update. Live ChatGPT service limits and future website changes can still affect very large uploads.

## 0.3.3 — Background Super Upload

### What's new

- Upload batches while using other apps or keeping ChatPretzel minimised.
- A new **Start batch upload?** dialog appears when you paste, drop, or choose more than 10 files. **Yes** or **Enter** starts the entire queue, including the first message. **No** sends nothing and preserves your draft.
- Your existing instruction is included above the first progress note. Each batch waits for ChatGPT to finish responding before the next batch is sent.
- The frosted progress screen locks the conversation against accidental changes while keeping **Cancel** available. Hiding or minimising the app does not cancel the queue.

### Reliability fixes

- Keep active uploads running without App Nap or automatic idle system sleep. On macOS 14 and later, temporarily disable WebKit's inactive-page suspension. Restore normal scheduling when the queue finishes or stops.
- Recognise completed responses when response controls fade in an inactive window, while still checking the current conversation, reply and idle state.
- Handle new-chat URL transitions, canonical conversation routes, long conversations and virtualised messages more reliably.
- Improve confirmation of image attachments and spreadsheet/table previews, including filename suffixes.
- Improve delayed-send handling, batch-state cleanup and stopped-queue reporting to reduce duplicate or premature sends.

Duplicate filenames remain supported through temporary upload-only copies; originals are unchanged. Clearly identified failed files are skipped and reported. Ambiguous failures stop the queue for review.

### Installation and limits

Download the DMG, open it, and drag ChatPretzel to Applications. Requires an **Apple Silicon Mac with macOS 13 or later**. The app is ad-hoc signed, not Developer ID signed or notarised. Use password sign-in if passkeys do not work in the embedded web view.

Super Upload is designed for regular **Chat**, not Work. Keep ChatPretzel open and connected. Manually sleeping the Mac, closing its lid or losing the connection can interrupt uploads. Cancelling does not retract messages already sent. ChatGPT's own account and upload limits still apply.

### Verification

- 72 JavaScript regression tests passed.
- Native AppKit/WebKit tests verified 25 files in 10 + 10 + 5 with the window hidden, preservation of the first draft, No sending nothing, and cancellation preventing later batches.
- The installed sandboxed build sent 21 synthetic files in 10 + 10 + 1 while minimised with Finder active. ChatGPT confirmed all 21 files. The maintainer also confirmed the build worked in normal use.
- The full XCTest suite remains unavailable with the selected local toolchain. Multi-hour runs, manual sleep recovery and every supported macOS version have not been independently verified.

This release packages the tested build 26 code with updated version metadata; no additional app features were added during release preparation.

ChatPretzel is an independent, unofficial project, not affiliated with, endorsed by, or sponsored by OpenAI.

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
