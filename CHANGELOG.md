# Ändringslogg

## 0.1.3-local — 2026-09-08

- Kopiering av markerad text från ChatPretzel skriver nu enbart ren text till urklippet, så Outlook inte ärver svart textfärg från ChatGPTs HTML.
- ChatGPTs knapp **Kopiera svar** går genom samma rena textväg.
- Verifierat i den installerade, inloggade appen: urklippet ändrades och innehöll textformat men inga HTML-format.
- JavaScript-adapterns testsats utökades från 19 till 24 tester.
- DMG-paketering använder en tillfällig systemmapp så File Provider inte kan återinföra Finder-metadata i den signerade appkopian.
- Uppdateringen är resursbaserad och använder den tidigare verifierade native-binären från 0.1.2. Ett nytt Swift-bygge är tillfälligt blockerat av en patchskillnad mellan installerad Swift-kompilator och macOS SDK.

## 0.1.2-local — 2026-09-08

- Bytte synligt appnamn till ChatPretzel utan att ändra intern WebKit-session eller bundle-ID.
- Använder `ny logo gpt.jpeg` som bildkälla och en textfri, kvadratisk kringelversion som appikon.
- Bytte app-, zip- och DMG-artefaktnamn till ChatPretzel.

## 0.1.1-local — 2026-09-08

- Rättade AppKit-delegatkonformans så att bibliotekspanelen kompilerar och fungerar.
- Rensar ZIP/Finder-metadata endast ur det temporära app-paketet före lokal signering.
- Verifierat releasebygge, ad-hoc-signatur, paketstorlek, appstart, bibliotekspanel och laddning av publika ChatGPT-sidan på arm64-Mac.
- Full inloggning, Finder-Cmd+V och verklig ChatGPT-uppladdning är fortsatt manuella tester.

## 0.1.0-source — 2026-09-08

Första källkodsleveransen. Native Swift/AppKit/WKWebView-projekt, säker fil-URL-handoff, pasteboard-läsare, lokal filstatus, normal webbfilväljare, nedladdningar, native prompt-/anteckningsbibliotek, utkast, sökning, zoom, genväg och felsäkert läge. Bygg-/signerings-/paketeringsskript och lokala fixtures.

44 portabla Swift-tester och 19 mockbaserade JS-tester passerade i Linux. Native Mac-kompilering, runtime, riktiga bilagor och prestanda återstår. Detta är inte en publicerad stabil release.
