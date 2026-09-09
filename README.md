<p align="center">
  <img src="Packaging/ChatPretzelIconSource.png" width="140" alt="ChatPretzel pretzel icon">
</p>

# ChatPretzel

An unofficial lightweight macOS client for ChatGPT.

ChatPretzel is for people who loved the focused ChatGPT Classic experience and still want ChatGPT in its own lightweight Mac window. As the official macOS app changed, many of us found that it no longer fit this simple workflow or worked reliably enough for our needs. We decided to build the alternative we wanted ourselves.

It keeps regular ChatGPT separate from Codex, so the two can run side by side: Codex for project and agent work, and ChatPretzel for conversations, research, and everyday questions. ChatPretzel uses Swift, AppKit, and the WebKit engine already included with macOS. It does not bundle Electron or Chromium and does not require an OpenAI API key.

## Features

- A single native macOS window for the regular ChatGPT website
- Runs as a separate app alongside Codex
- Normal ChatGPT login and session handling through WebKit
- Multi-format attachments through normal file selection, with experimental attachment paste from Finder and Apple Mail
- Local prompts, bookmarks, notes, and draft tools
- Search, zoom, reading width, and a global window shortcut
- Voice input through ChatGPT with macOS microphone permission; camera access remains blocked
- Plain-text copying that avoids dark text formatting when pasting into Outlook
- App Sandbox with no cookie import, token extraction, or background service

## Download and use

Download the [latest ChatPretzel DMG installer from GitHub Releases](https://github.com/vaasques/ChatPretzel/releases/latest), open it, and drag `ChatPretzel.app` to Applications. Then open the app and sign in to ChatGPT with your account password.

**Sign-in note:** Passkey sign-in does not currently work reliably inside ChatPretzel's embedded WebKit window. If ChatGPT or Google offers a passkey, choose another sign-in method and enter your password instead. An OpenAI API key is not required.

The current downloadable build is made for Apple Silicon, ad-hoc signed, and not notarized. macOS may therefore show its normal warning for software downloaded outside the App Store. The source is available here for inspection.

To paste attachments, copy files in Finder or selected attachments in Apple Mail, focus ChatGPT's message field, and press Command+V. Wait until the files appear in ChatGPT before sending your message. Mail attachment paste is experimental and the app does not claim that the server accepted a file until you can see it in ChatGPT.

To use voice input, click the microphone in ChatGPT and allow microphone access when macOS asks. If access was denied earlier, enable ChatPretzel in **System Settings → Privacy & Security → Microphone**, then reopen the app. ChatPretzel grants microphone requests only to the ChatGPT page and continues to block camera access.

To build from source, use macOS 13 or later with a matching Apple Swift toolchain and macOS SDK, then run:

```sh
bash scripts/build.sh
```

The finished app is placed in `dist/ChatPretzel.app`.

## Support ChatPretzel

ChatPretzel is free and open source. If you find it useful, you can support continued development with a crypto donation:

- **Bitcoin (BTC), Bitcoin network:** `3JAw4YbohcMSX89LPWEnZLf5WBWAfHn887`
- **Ethereum (ETH), Ethereum (ERC20) network:** `0xebcd637468096ac8dd6ed7c10342edac8fc4ba46`
- **USD Coin (USDC), Solana network:** `DLxwmRNF8BHSkaBx9ieJLQwc46dgFvRuSuyrGTkSndrh`

Send only the listed asset using the exact network shown. Crypto transfers are irreversible, and funds sent using the wrong asset or network may be lost.

## Unofficial project

ChatPretzel is an independent, unofficial project. It is not affiliated with, endorsed by, or sponsored by OpenAI. ChatGPT and OpenAI are trademarks of their respective owner. Use of the ChatGPT service remains subject to OpenAI's terms and availability.

## License

ChatPretzel is available under the [MIT License](LICENSE).
