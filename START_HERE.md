# Install ChatPretzel

1. Drag `ChatPretzel.app` to the Applications folder.
2. Open ChatPretzel from Applications.
3. Sign in to ChatGPT using your account password.
4. To paste up to 10 attachments, copy files in Finder or selected attachments in Apple Mail, focus the ChatGPT message field, and press Command+V. Check that every attachment appears, then send normally.
5. Write your instruction, then paste, drop, or choose more than 10 files. At **Start batch upload?**, choose **Yes** or press **Enter** to start all batches automatically, including the first message. **No** sends nothing. ChatPretzel waits for each ChatGPT response before sending the next batch of up to 10 files. A frosted progress screen prevents accidental chat changes and provides **Cancel**. You can use other apps or minimise the window while it runs; keep ChatPretzel open and connected.
   Duplicate filenames receive upload-only suffixes such as ` 2` and ` 3`; originals stay unchanged and temporary copies are removed automatically. Failed files are skipped only when they can be identified safely, and the progress notes report the revised totals. Cancellation does not retract messages already sent. Manually sleeping the Mac or closing its lid can still interrupt uploads.
6. Unsupported or unreadable files are skipped and reported. ChatGPT's own upload, storage, and rate limits still apply, so review the finished conversation.
7. To dictate, click the microphone in ChatGPT and choose **Allow** when macOS asks. If you denied it earlier, enable ChatPretzel in **System Settings → Privacy & Security → Microphone**, then reopen the app.

**Important sign-in note:** Passkey sign-in does not currently work reliably inside ChatPretzel's embedded WebKit window. If ChatGPT or Google offers a passkey, choose another sign-in method and enter your usual password instead. You do not need an OpenAI API key.

ChatPretzel is ad-hoc signed and not notarized. If macOS blocks the first launch, Control-click the app, choose **Open**, and confirm.

ChatPretzel is an independent, unofficial project. It is not affiliated with or endorsed by OpenAI.
