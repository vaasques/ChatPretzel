# Tekniska primärkällor

Kontrollerade i samband med implementationen 2026-09-08. Dokumentationen beskriver API-kontrakt, inte att denna app är byggd eller att riktig ChatGPT accepterar flödet. Använd aktuell SDK-deklaration vid Mac-kompileringen.

- Apple WKWebView: https://developer.apple.com/documentation/webkit/wkwebview
- Native filväljarcallback, WKUIDelegate: https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:runopenpanelwith:initiatedbyframe:completionhandler:)
- WKOpenPanelParameters: https://developer.apple.com/documentation/webkit/wkopenpanelparameters
- NSPasteboard: https://developer.apple.com/documentation/appkit/nspasteboard
- Apple file-promise/fil-URL exempel: https://developer.apple.com/documentation/appkit/supporting-table-view-drag-and-drop-through-file-promises
- WKContentWorld: https://developer.apple.com/documentation/webkit/wkcontentworld
- callAsyncJavaScript: https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)
- WKDownload: https://developer.apple.com/documentation/webkit/wkdownload
- Nedladdningsdestination: https://developer.apple.com/documentation/webkit/wkdownloaddelegate/download(_:decidedestinationusing:suggestedfilename:completionhandler:)
- Avbryta nedladdning: https://developer.apple.com/documentation/webkit/wkdownload/cancel(_:)
- Åtkomst i App Sandbox: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox

Ingen motsvarande källa garanterar att JavaScript-`.click()` i ett isolerat content world alltid triggar en viss webbplats native filväljare. Den punkten är uttryckligen ett verifieringskrav, inte ett dokumentationsbevis.
