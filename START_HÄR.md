# Starta ChatPretzel på din Mac

Källkods-ZIP:en och den färdiga app-ZIP:en levereras separat. ChatPretzel 0.1.3 är installerad och startad på den verifierade Apple Silicon-Macen. En lösenordsinloggad ChatGPT-session och Outlook-säker ren textkopiering har kontrollerats live. Finder-Cmd+V med blandade bilagor är fortfarande inte slutgodkänt.

0.1.3 ändrar webbadaptern och versionsresurserna ovanpå den tidigare verifierade native-binären från 0.1.2. Ett helt nytt Swift-bygge är tillfälligt blockerat på den aktuella värden eftersom Swift-kompilatorn och macOS SDK-standardbiblioteket har olika patchversion. Byggskriptet stannar vid det verkliga felet i stället för att producera en fejkad ny binär.

## 1. Bygg

Packa upp hela ZIP-filen. Behåll katalogstrukturen. Mac-appens kod kräver macOS 13 eller senare och en kompatibel Apple-utvecklingsmiljö med Swift 5.9 eller senare samt macOS SDK.

Öppna `Bygg ChatPretzel.command` i den uppackade mappen. Skriptet kontrollerar verktygen, bygger Swift-programmet, skapar appikon och app-paket, signerar **det nya lokala bygget** ad-hoc och verifierar resurser och storlek. Det ändrar inte dina befintliga ChatGPT-/Codex-installationer eller globala säkerhetsinställningar.

Vid lyckat bygge öppnas `dist/ChatPretzel.app`. Ett tidigare bygge i samma `dist` sparas under ett nytt namn. Kopiering till `/Applications` är valfri och sker inte automatiskt.

Samma byggning från Terminal, med projektmappen som aktuell katalog:

```sh
bash scripts/build.sh
open dist/ChatPretzel.app
```

**Saknas Apple-verktyg?** Installera lämpliga Xcode/Command Line Tools via Apples vanliga flöde. Det behövs för att kompilera här, inte som bakgrundsprocess när den färdiga appen används. Skriptet laddar inte ner verktyg åt dig.

En ad-hoc-signerad app är **inte notariserad**. Följ macOS normala gransknings-/öppningsflöde om systemet blockerar öppning. Stäng inte av Gatekeeper eller sandbox och kör inte appen som root.

## 2. Testa filerna lokalt först

Välj `Hjälp → Öppna lokalt filtest…`. Markera alla sex filer i `Fixtures/files` i Finder. Cmd+C, växla till appen, skriv `BEHÅLL MIN TEXT`, fokusera fältet och Cmd+V en gång.

Mottagaren ska visa **sex filer och sex korrekta SHA-256**, utan att texten försvinner. Det är ett lokalt filöverföringstest, inte en ChatGPT-uppladdning. Kontrollera sedan samma flöde mot riktig ChatGPT med syntetiska testfiler, inte arbetsgivarens känsliga dokument. Se `docs/CLIPBOARD_TESTS.md`.

## 3. Logga in och kontrollera den verkliga chatten

Tryck Ny chatt för att återgå till ChatGPT. Logga in manuellt. Importera inte cookies eller sessionstokens. Pröva modellval, en vanlig fråga och därefter det exakta blandade Finder-paste-testet. Appen ska inte skicka meddelandet åt dig.

Får du `Ingen befintlig filkontroll accepterar hela urvalet` eller en WebKit-timeout är det en **riktig blockerare**, inte bevis på att en fil har bifogats. Filväljare eller drag-and-drop kan hjälpa till att avgränsa felet men ersätter inte kravet på Cmd+V.

## 4. Vid byggfel eller buggar

`test-results/mac-build.txt` innehåller byggutdata. `Hjälp → Exportera teknisk diagnostik…` skapar en innehållsfri rapport när appen går att starta. Beskriv sedan vad du gjorde, förväntat utfall och faktiskt utfall. Bifoga koden och lämplig rapport i Codex med `HANDOFF_TO_CODEX.md`.

Granska skärmbilder, kraschrappporter och byggloggar före delning. De kan innehålla användarnamn, lokala sökvägar eller chattinnehåll även när appens egen diagnostik inte gör det.

## Felsäkert läge

Avsluta appen först och starta sedan:

```sh
open dist/ChatPretzel.app --args --safe-mode
```

Det stänger av egna webbskript utan att radera ditt konto eller bibliotek. Det bevisar inte blandad paste, men isolerar fel i våra tillägg från vanlig WebKit-/webbfunktion.

## Native tester och valfri DMG

```sh
bash scripts/test-macos.sh
bash scripts/package.sh
```

Mac-testerna kräver en grafisk Mac-session. De använder privat testurklipp, egen preferensdomän, tillfällig bibliotekskatalog och icke-beständig WebKit-session. DMG skapas endast efter ett lyckat lokalt appbygge; paketering är inte samma sak som notarisering eller live-godkännande.
