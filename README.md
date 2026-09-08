<p align="center">
  <img src="Packaging/ChatPretzelIconSource.png" width="140" alt="ChatPretzel pretzel icon">
</p>

# ChatPretzel

An unofficial lightweight macOS client for ChatGPT.

ChatPretzel exists for people who prefer a small, focused desktop window instead of keeping another browser tab open. It uses Swift, AppKit, and the WebKit engine already included with macOS. It does not bundle Electron or Chromium and does not require an OpenAI API key.

## Features

- A single native macOS window for the regular ChatGPT website
- Normal ChatGPT login and session handling through WebKit
- Experimental Finder file paste, plus normal file selection and download handling
- Local prompts, bookmarks, notes, and draft tools
- Search, zoom, reading width, and a global window shortcut
- Plain-text copying that avoids dark text formatting when pasting into Outlook
- App Sandbox with no cookie import, token extraction, or background service

## Download and use

Download the [ChatPretzel DMG installer from Gumroad](https://prooveva.gumroad.com/l/chatpretzel), open it, and drag `ChatPretzel.app` to Applications. Then open the app and sign in to ChatGPT normally.

The current downloadable build is made for Apple Silicon, ad-hoc signed, and not notarized. macOS may therefore show its normal warning for software downloaded outside the App Store. The source is available here for inspection.

To build from source, use macOS 13 or later with a matching Apple Swift toolchain and macOS SDK, then run:

```sh
bash scripts/build.sh
```

The finished app is placed in `dist/ChatPretzel.app`. Build and test details are documented in [TEST_REPORT_MACOS.md](TEST_REPORT_MACOS.md).

## Support ChatPretzel

ChatPretzel is free and open source. If you find it useful, you can support continued development through Gumroad.

[Download ChatPretzel or support the project on Gumroad.](https://prooveva.gumroad.com/l/chatpretzel)

## Unofficial project

ChatPretzel is an independent, unofficial project. It is not affiliated with, endorsed by, or sponsored by OpenAI. ChatGPT and OpenAI are trademarks of their respective owner. Use of the ChatGPT service remains subject to OpenAI's terms and availability.

## License

ChatPretzel is available under the [MIT License](LICENSE).
