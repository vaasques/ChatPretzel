# Testprotokoll — levererad källversion 0.1.0

Datum: 2026-09-08. Miljö: Linux x86_64, Swift 6.2.1 (Swift language mode 5), Node 22.16.0. Ingen macOS SDK eller AppKit/WebKit-runtime fanns tillgänglig.

| Kontroll | Utfall | Vad det faktiskt bevisar |
|---|---|---|
| `swift build --target ChatDeskCore` | PASS | Portabel Foundation-kod kompilerar på Linux. |
| XCTest `ChatDeskCoreTests` | **44 / 44 PASS** | Navigeringspolicy, engångstillstånd, URL-urval, statusmaskin, lokal lagring, utkast och promptvariabler. |
| `node --test Tests/Web/adapter.test.mjs` | **19 / 19 PASS** | Adapterlogik mot liten mock-DOM. Ingen verklig browser-filväljare. |
| Syntaxparse av samtliga app-/test-Swift-filer | PASS | Swift-syntax; **inte** Apple SDK-symboler, protokollkrav eller ABI/link. |
| Foundation-only `LibraryController` typecheck med stubbat FileAccessLease | PASS | En identifierad queue/actor-gräns har kontrollerats separat. Inte native end-to-end. |
| Byggskript `bash -n`, XML/plist-läsning | PASS | Shell-/plist-syntax; inte körda Mac-kommandon eller signering. |
| `check-fixtures.py` | **6 / 6 PASS** | Originalens SHA-256/längd, Office-container och PDF-header. Ingen transfer. |
| Visuell granskning av syntetisk PDF/DOCX/XLSX | PASS | Testoriginalen är riktiga, läsbara dokument, inte bara omdöpta textfiler. Appens UI har inte renderats. |
| Chromium browser-fixture | **BLOCKED** | Administratörspolicy stoppade navigering (`ERR_BLOCKED_BY_ADMINISTRATOR`) innan några assertions. Ingen policy ändrades. |
| Native `NSPasteboard`-tester (4 st) | **EJ KÖRDA** | Finns i källkoden, kräver Mac. |
| Native `WKWebView`-filbridge-test (1 st) | **EJ KÖRT** | Finns i källkoden, kräver Mac med grafisk session. |
| Mac-bygge, `.app`, ikon, signering, DMG | **EJ KÖRT** | Leveransen innehåller inte dessa binärer. |
| Normal inloggning, modellval, screenshot-paste, C01/C15 | **EJ KÖRT** | Kräver Mac och användarens verkliga konto. |
| Releaseprestanda, total WebKit-belastning | **EJ MÄTT** | Det finns budgetar och en mätmetod, inte uppmätta resultat. |

## Råbevis

`test-results/core-tests.txt`, `adapter-tests.txt`, `core-build.txt`, `native-parse.txt`, `library-concurrency-check.txt`, `fixture-integrity.txt`, `browser-fixture.json`, `source-validation.txt`.

Browser-försöket får **inte** räknas som ett passerat integrationstest. Mock-DOM-testet får **inte** användas som bevis för att WebKits `runOpenPanel` triggas. Mac-enhetstestet använder direkt test-URL-urval och bevisar, även om det senare passerar, inte hela Finder-/sandbox-hotkey-kedjan.

## Säkerhetsrelaterade fall som täcks av portabla tester

Lookalike-hosts, osäkra protokoll, userinfo/icke-standardport, lokala filer utanför fixture, fjärrhost maskerad som fixture, utgånget/återanvänt permit, sid-/dokument-/generationsbyte, subframes, dubbla filrepresentationer, samma filnamn i olika kataloger, korrupt fil som inte skrivs över, okänd lagringsversion, storleksgränser, tillfälliga chattar, ingen utkastöverskrivning samt ingen automatisk formulärsändning i mocken.

## När Codex kör på Mac

Lägg till resultat med faktisk OS/CPU/SDK, exakt bygg-ID, testmetod och datum. Märk varje rad PASS/FAIL/BLOCKED/EJ KÖRT. Ändra inte detta Linux-protokoll till ett Mac-PASS; skapa en separat Mac-rapport och uppdatera STATUS med nya bevis.
