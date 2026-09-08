# Arkitektur

## Processer och appgrund

`ChatDeskApp` startar `NSApplication`. `ChatDeskMac` äger native UI och systemets WKWebView. `ChatDeskCore` innehåller vanlig Foundation-logik och kan testas utan macOS. Inga tredjepartspaket behöver lösas. Ett huvudfönster skapas; paneler skapas först vid användning. Normal autentiseringspopup får tillfälligt ha en extra webbvy med den konfiguration WebKit lämnar.

WebKit kan ha flera hjälpprocesser även med en webbvy. Koden försöker inte ändra detta eller hindra systemets energihantering. Att appfönstret är dolt leder inte till en avsiktlig reload/stop, men kontinuerlig servergenerering i bakgrunden är inte garanterad eller testad.

## Urklipp till riktiga bilagor

1. `ChatWindow` och menyn fångar en uttrycklig paste-gest när huvudwebbvy har fokus.
2. `ClipboardReader` läser samtliga typer/poster. Faktiska file-URL-poster prioriteras över filnamn och previews. Vanliga textvägar är text, inte filbehörighet. Råbild/text går vidare till normal system-paste.
3. `FileSelection` håller ett snapshot av URL-objekt och deduplicerar enbart samma standardiserade URL inom operationen, aldrig enbart filnamn. Ny avsiktlig paste är en ny operation.
4. Native scopes behålls genom `FileAccessLease`. Validering körs på serial I/O-kö. Mappar, paket, symboliska länkar, otillgängliga filer och identifierade molnplatshållare nekas. Ingen fil läses till ett helt Data/base64-objekt för appens transfer.
5. `WebAdapter` anropar en liten lokal JS-adapter i separat WKContentWorld. Bara exakt ChatGPT-origin eller exakt medföljande fixture får nå den.
6. En engångscapability binds till dokument-ID, exakt sida, native navigeringsgeneration och fem sekunders timeout. Webbsidan får inga filpaths eller godtyckliga filsystemskommandon.
7. Adaptern söker en befintlig entydig input som accepterar samtliga typer. Den får inte ändra accept/multiple eller skapa en ny input. En klickbegäran öppnar förhoppningsvis WebKits riktiga filväljarkedja.
8. `WKUIDelegate` validerar aktiv capability, frame, dokument och klickad input igen. Endast sedan returneras original-URL:er till WebKit.
9. Lokal status blir **överlämnad**, inte **uppladdad**. Användaren granskar webbens riktiga status. Appen skickar aldrig prompten.

Punkt 7–9 är Mac-/live-gaten. Plattformen kan neka att `.click()` öppnar filväljaren; ChatGPT kan sakna en entydig passande input eller ändra editor. Då visas ett verkligt fel utan automatisk alternativmotor. Ingen del av Linux-testningen bevisar denna kedja.

Känd begränsning: om en webbapplikation byter konto utan upptäckbar sid-/dokumentändring kan kontoidentiteten inte bevisas. Funktionen får inte kallas kontoisolerad utan manuellt test. Automatisk lagring/återinsättning över kontoidentiteter är inte implementerad.

## Tillstånd och livslängder

Filstatus: identified → checking → waitingForWebKit → handedToWebKit. Därefter antingen manuell userConfirmed eller unknown vid sidbyte. Fel och avbryt före handoff är separata. Efter handoff låtsas appen inte kunna återkalla serveruppladdningen.

Högst en lokal filoperation i taget, 100 lokala filer per batch, åtta behållna lease-batcher och 500 lokala statusrader. Rader med okänd slutstatus kan rensas som historik, utan att detta blir en uppladdningsbekräftelse. Den globala tillståndslistan persisteras inte.

En OS-fil-URL avser en fil som fortfarande kan ändras av användaren/andra program. Redigera inte filerna under pågående överföring. Koden hävdar inte att den tar ett oföränderligt snapshot av bytes; fixturens kontrollsummor testar faktiskt mottagna bytes i ett kontrollerat fall.

## Nedladdningar

WebKit överlämnar `WKDownload`; native NSSavePanel väljer destination. Befintlig fil nekas i stället för att raderas. URL-/resumedata loggas inte. Högst åtta aktiva nedladdningar; avslutad rad-historik begränsas. Ingen återupptagning eller beräknad procent ännu.

## Bibliotek och utkast

`LibraryStore` har versionsmärkt JSON, högst 500 poster, fem MiB filgräns, atomisk skrivning och föregående version som backup. Korrupt/okänd version orsakar read-only-fel, inte ny tom databas ovanpå originalet. Skrivning serialiseras utanför UI-tråden. Vid avslut kontrolleras att skrivkön är färdig och att senaste skrivningen lyckades.

Textutkast buffras bara i sessionens minne (20 poster, gräns per text). Explicit Spara utkast lägger en vanlig lokal biblioteks-post på disk. Återställning kräver användarbekräftelse och tom editor. Tillfälliga chattar nekas för explicit sparning när de identifieras; ingen automatisk disk-persistens sker för några chattar.

## Byggning

SwiftPM kompilerar programmet. Byggskriptet packar explicita lokala resurser, genererar en egen liten AppKit-ikon och signerar med snäva sandbox-entitlements. SwiftPMs genererade `Bundle.module` används bara som utvecklingsreserv; den paketerade appen läser `Contents/Resources/ChatDeskAssets`. Detta undviker att den packade appen behöver filer ur utvecklarens absoluta byggkatalog.
