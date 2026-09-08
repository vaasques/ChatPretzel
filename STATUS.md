# Status — 2026-09-08

Version: **0.1.3, personlig lokal utvecklingsversion**. Synligt namn: **ChatPretzel**. Extern release: **NEJ**. Installerad app/start: **PASS**.

## Ny Mac-verifiering

På macOS 26.6.2/arm64 är ChatPretzel 0.1.3 installerad, lokalt ad-hoc-signerad och startad med en fungerande inloggad ChatGPT-session. Installerad storlek är 3420 KiB inklusive den textfria appikonen. Kopiering via ChatGPTs **Kopiera svar** har verifierats mot det verkliga macOS-urklippet: ren text finns och HTML-format saknas, vilket hindrar Outlook från att ärva en fast svart textfärg. Markeringskopiering använder samma sanitiseringsväg och täcks av enhetstest. Ett användarutfört filväljartest läste tidigare sex filer utan läsfel, men det var inte de medföljande fixture-filerna och inte Finder-Cmd+V.

0.1.3 är en resursuppdatering ovanpå den tidigare byggda och verifierade 0.1.2-binären; native Swift-logiken ändrades inte. Ett helt nytt Swift-bygge kunde inte utföras eftersom värdens Swift-kompilator (`swiftlang-6.2.1.4.8`) och SDK-bibliotek (`swiftlang-6.2.1.4.7`) har olika patchversion. Full native XCTest är dessutom fortsatt blockerad eftersom endast Command Line Tools utan XCTest finns installerat. Se `TEST_REPORT_MACOS.md`.

## Genomfört i denna leverans

Källkoden, lokala resurser, syntetiska fixtures, bygg-/paketeringsskript och tester är skrivna. Portabel Swift-logik och 24 mockbaserade JS-enhetstester har körts. Den installerade appen är paketerad, signerad och startad. Den nya kopieringsvägen är dessutom kontrollerad i den riktiga inloggade appen. Fullt nytt Swift-bygge, full XCTest och de manuella Finder-/bilagetesterna återstår.

## Kravläget

| Krav | Implementation | Faktiskt godkännande |
|---|---|---|
| Native AppKit/WebKit, inga tunga runtimepaket | Skriven; inga externa Swift-beroenden | Paketerat arm64-Mac-bygge PASS. |
| Normal ChatGPT-inloggning/session/modellväljare | Webbvy och normal auth-popup | PASS för befintlig lösenordsinloggad session. Google/annan provider är inte separat verifierad och kan blockera inbäddad inloggning. |
| Kopiera markerad text/svar till Outlook | Trusted copy-event rensar rik text och skriver `text/plain` | PASS live för **Kopiera svar**: urklippet ändrades, texten stämde och HTML-format saknades. Markeringsvägen 24/24 JS-testad. |
| C01: sex blandade Finder-filer, en Cmd+V | URL-läsare, säker native handoff, dokumentguard | **EJ KÖRT på Mac eller ChatGPT.** |
| C02: meny-paste | Native meny använder samma väg | EJ KÖRT. WebKits högerklicksmeny är inte verifierad att nå samma hook. |
| C03–C10: urval/filidentitet/races | Portabel logik och fail-closed guards | Enhetstester PASS, native/live återstår. Konto utan URL-byte särskilt otestat. |
| C11–C13: screenshot/text/fokus | Normal WebKit-path eller fokuserad native path | EJ KÖRT i riktig AppKit-responder chain. |
| C14: faktisk lokal File API/bytes | Sex giltiga original + hashmottagare + WK-test | Originalens integritet PASS; WK-överföringen **EJ KÖRD**. |
| C15: riktiga serverbilagor | Synlig uppdelning av överlämnad/manuellt verifierad | EJ KÖRT; inga falska serverkvitton. |
| Nedladdning | WKDownload, sparpanel, avbryt, Finder | EJ KÖRT. Procent/resume ingår inte ännu. |
| R01: bakgrund/nät/vila | Inga automatiska omsändningar; felhantering | EJ KÖRT på Mac. |
| R02: full utkaståterhämtning | Sessionsbuffert + explicit save/restore | **DELVIS IMPLEMENTERAT.** Automatisk beständig kontosäker buffert återstår. |
| R03: tillfällig chatt | Ingen automatisk diskpersistens; kända signaler nekar manual save | Enhetstest av signaler PASS; liveändringar återstår. |
| R04: felsäkert läge | Av/på för egna script, bibehållet eget datastore | EJ KÖRT på Mac. |
| Promptbibliotek/egna bokmärken/anteckningar | Native UI + versionerat JSON-lager | Lagringslogik PASS; panelens smoke-test PASS, full E2E återstår. |
| P01/P02: resursbudgetar | Liten arkitektur och paketgränskontroll i skript | **INTE MÄTT.** |

## Avsiktligt inte byggt i denna version

Komplett meddelandetidslinje, modifiering av serverhistorik/mappar, osynlig kontosynk, automatisk chatt-export, röstläge, en andra snabbchatt, full Chrome-extension-kompatibilitet, nätverksbaserad uppdaterare och installerad bakgrundstjänst.

## Nästa steg — håll fast vid grundflödet

1. Matcha Swift-kompilator och macOS SDK, bygg sedan om och kör Mac-testerna utan resursuppdaterningens tillfälliga binäråteranvändning.
2. Kör den faktiska sandboxade appen mot lokal filmottagare; testa **Finder Cmd+C/Cmd+V**, inte bara att testkoden får skicka URL:er.
3. Testa normal inloggning och samma paste mot riktiga ChatGPT med de syntetiska filerna.
4. Rätta det verkliga lagret som fallerar: pasteboard/scopes, responder chain, WebKit-gesture, input-matchning eller webbtjänsten.
5. Först efter godkänd grund: mät prestanda och slutför R02/övriga luckor.

Arbeta från `HANDOFF_TO_CODEX.md`. En kompilerande `.app` eller sex lokala statusrader får inte användas som ersättning för C01/C15.
