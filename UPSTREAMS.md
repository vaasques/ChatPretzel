# Ursprung och beroenden

Version 0.1.0 innehåller ny implementation för detta uppdrag. Inga filer från `lencx/ChatGPT`, `electron-browser-shell`, `chatgpt-voyager` eller `GravityPoet/chatgpt-web-desktop` har kopierats in. De tidigare projekten har diskuterats som referenser, men är inte paketerade beroenden eller aktiva forks i denna leverans.

Swift Package Manager anger `dependencies: []`. Appens runtime använder systemets AppKit, WebKit, Carbon, Foundation och UniformTypeIdentifiers. Systemfonter/SF-symboler används via OS vid runtime; inga fontfiler medföljer. Ikonen genereras av ett litet eget AppKit-byggskript.

De sex fixturefilerna har skapats syntetiskt för testet. Ingen privat chatt, användarfil, arbetsgivarfil eller inloggningsdata medföljer. PDF/Office-renderingsverktyg användes bara för att skapa/granska testfilerna, inte som appberoenden.

Node och Python/Playwright förekommer endast i valfria utvecklingstester; de ska aldrig paketeras eller krävas när appen körs. `scripts/build.sh` behöver inte dessa verktyg.

Projektets egen källkod publiceras under MIT-licensen. Det innebär inte någon licens till OpenAI- eller ChatGPT-varumärken. ChatPretzel är ett fristående, inofficiellt projekt och är inte anslutet till eller godkänt av OpenAI. Införs extern kod senare ska repo, full commit-SHA, licens, exakta filer och modifieringar dokumenteras här och nödvändiga notices bevaras.
