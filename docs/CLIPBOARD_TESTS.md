# Testa hela filkedjan

Detta är en manuell checklista, **inte** ett protokoll över redan passerade tester.

## Tre olika nivåer — blanda inte ihop dem

**A: representationer.** Läs sex NSPasteboard-poster och kontrollera original-URL:er. Native XCTest täcker läsaren med privat testurklipp. Det skapar inte Finders riktiga sandbox-grants.

**B: lokal faktisk byteöverföring.** Kör den byggda sandboxade appen och medföljande filmottagare. Finder-kopiera alla sex original i `Fixtures/files`. Ett Cmd+V ska ge sex korrekta hashresultat. Native WK-test hjälper till att avgränsa callbackvägen men använder direkt test-URL-urval, inte Finder.

**C: tjänsten.** Logga in manuellt i riktiga ChatGPT. Kör samma Finder-paste. Alla sex ska visas som riktiga färdiga bilagor, i rätt chatt, utan att behöva väljas om. Det är **C01/C15** och huvudkravet.

## Originalen

`Fixtures/manifest.json` anger namn, storlek och SHA-256 för sex giltiga små PDF/DOCX/XLSX/PNG/JPG/TXT. Dokumenten innehåller unika synliga markörer. En separat mapp kan senare innehålla två andra filer med samma namn för C06; ändra inte manifestets original för att få ett test att passera.

## Obligatorisk körning

| Fall | Kontroll |
|---|---|
| Sex blandade original, en paste | Alla sex, ingen omselektion, ingen automatisk prompt-sändning. |
| Redigera → Klistra in | Samma flöde, inga nya filval. |
| Högerklicksmeny → Klistra in | Verifiera separat. Native interception är ännu inte bevisad för WebKits kontextmeny. |
| Befintlig prompt och tidigare bilaga | Båda finns kvar efter nya bilagor. |
| Samma filtyp flera gånger | Alla filposter hanteras, inte bara första item/typen. |
| Två kataloger, samma filnamn | Båda originalen finns. Dedupe är inte enbart filnamn. |
| Kopierad JPG-fil vs riktig skärmbild | JPG är originalfil; rå skärmbild går genom systemets bild-paste. |
| Vanlig kod/text med åäö och radbrytningar | Ingen filtolkning av textvägar. Text kommer in oförvanskad. |
| Urklipp ändras efter paste-start | Redan startad operation ändrar inte sitt filurval. |
| Chatt-/kontobyte mitt i operation | Inga bilagor läcker till ny chatt eller identitet. Testa även kontoändring utan URL-byte. |
| En borttagen/otillgänglig fil | Tydligt fel. Aktuell version stoppar hela urvalet före handoff. |
| Klicka paste två gånger avsiktligt | Ingen oavsiktlig dubbelhantering av en gest; andra gesten under väntan nekas tydligt. |
| Paste i lokalt sök-/namnfält | Ingen uppladdning till webbsidan. |
| 20 upprepningar / 20 sidbyten | Inga växande resurser eller kvarhängande behörighetsbatcher. |

## Så avgränsas ett fel

- Filantal saknas redan lokalt: `ClipboardReader`/Finder-format.
- URL:er finns men kan inte öppnas: sandbox-grants, molnfil, lokal filåtkomst.
- Kompositorn saknas eller input är tvetydig: aktuell `Adapter.js`-matchning.
- `.click()` begärd men native callback uteblir: WebKit user-gesture-/filväljarintegration.
- Callback har fått rätt URL:er men lokal hash misslyckas: WebKit-läsning, scopes eller File API.
- Lokal bytekontroll passerar men riktig ChatGPT misslyckas: tjänstens verkliga DOM/uppladdning/gränser. Det är inte ett godkänt användarflöde.

Spara lokal rapport via mottagarens knapp. Den innehåller **syntetiska filnamn och hashvärden**, inte filer. För riktiga arbetsfiler kan även filnamnen vara känsliga; använd inte dessa vid delning.

Filer som ändras av andra program under uppladdning har inte frysta bytes. Stäng/redigera inte originalen under det kontrollerade testet. Råbilds- och fil-paste måste provas separat; ena fallet bevisar inte det andra.
