# Mac-testprotokoll — ChatPretzel 0.1.3-local

Datum: 2026-09-08. Miljö: macOS 26.6.2 (25G83), arm64, Apple Swift 6.2.1. Swift-kompilatorn rapporterar `swiftlang-6.2.1.4.8`, medan installerat SDK-standardbibliotek rapporterar `swiftlang-6.2.1.4.7`. Endast Command Line Tools är installerat; full Xcode/XCTest saknas.

| Kontroll | Utfall | Bevisgräns |
|---|---|---|
| `ChatDeskCore` releasebygge | PASS | Portabel Swift-kärna kompilerar. |
| JavaScript-adapter | 24/24 PASS | Mock-DOM; omfattar markeringskopiering, betrodd copy-event, skydd mot syntetisk copy samt ChatGPTs kopieringsknapp. |
| Fixture-integritet | 6/6 PASS | Medföljande original och hash, inte överföring. |
| Tidigare releasebygge av native-binären | PASS, 0.1.2-bas | Native AppKit/WebKit-programmet kompilerades och länkades före 0.1.3. Native Swift-logiken ändrades inte i 0.1.3. |
| Ny full Swift-kompilering för 0.1.3 | BLOCKED | Swift-kompilatorns och SDK-standardbibliotekets patchversioner skiljer sig. Felet uppstår innan projektets källkod kompileras. |
| App-paket och resurser | PASS | `Adapter.js`, fixture, plist och arm64-binär finns. |
| Lokal ad-hoc-signatur och sandbox | PASS | Strikt signaturkontroll; sandbox, nätverksklient och användarvalda filer. Inte Developer ID/notarisering. |
| Installerad appstorlek | PASS, 3420 KiB | Inklusive textfri kringelikon; under projektets 30 MiB-budget. |
| Namn och ikon | PASS-smoke | Installerad app, fönster, meny och process heter ChatPretzel; ICNS förhandsgranskades utan ChatGPT-text. |
| Appstart i fixture-läge | PASS | Huvudfönster och lokal mottagare visas; processen förblir igång. |
| Leveranszip, vanlig start utan flaggor | PASS | Uppackad app går direkt till `https://chatgpt.com/`; lokal fixture visas inte. |
| Lokalt bibliotek | PASS-smoke | Panelen öppnas och fälten visas efter delegatfixen. |
| Inloggad ChatGPT-sida | PASS-smoke | Befintlig lösenordsinloggad session laddas, konversation och skrivfält visas. Ingen inloggningsuppgift lästes eller flyttades. |
| **Kopiera svar** till macOS-urklipp | PASS live | Klick i den installerade appen ökade urklippets ändringsräknare från 1650 till 1651. Texten stämde. `public.html` och `Apple HTML pasteboard type` saknades; endast ren text plus WebKits interna ursprungsmetadata fanns. |
| Markerad text → Cmd+C | PASS i enhetstest, EJ MANUELLT KÖRT | Samma betrodda copy-handler skriver endast `text/plain`. Live-knapptestet ovan kör samma sanitiseringsväg. |
| Användarens lokala filrapport | PASS-deltest | En filväljaroperation läste sex filer och beräknade hash utan fel; inga formulär skickades. Filerna var inte de sex fixtures och källan var `real-file-input-change`, inte Finder-Cmd+V. |
| Native XCTest | BLOCKED | `no such module 'XCTest'`; full Xcode saknas. |
| Finder → en Cmd+V → sex fixtures | EJ KÖRT | Kräver faktisk Finder-gest och användarverifiering. |
| Inloggad ChatGPT-uppladdning C01/C15 | EJ KÖRT | Kräver användarens egen inloggning och uttryckliga uppladdningstest. |
| Full prestandaserie | EJ KÖRT | Paketstorlek är mätt; CPU/RAM/start-p95 återstår. |

Slutsats: installerad och startbar personlig lokal prototyp med live-verifierad ren textkopiering för Outlook. Den får inte beskrivas som nykompilerad i 0.1.3, eller som verifierad för Finder-Cmd+V/verklig ChatGPT-filuppladdning, förrän de respektive blockerade/manuella testerna passerat.
