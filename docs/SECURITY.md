# Säkerhetsgränser och integritet

## Ingen annan chattmotor

Appen använder normal ChatGPT-webb. Den ersätter inte servermodeller, kontogränser eller verktyg med egna API-/Codex-anrop. Ingen cookieimport, tokenextraktion, inloggningsbypass eller privat historikexport finns implementerad.

## Fjärrsidan är inte betrodd native kod

Adaptern körs i separat `WKContentWorld`. Native kontrollerar meddelandetyp, storlek, huvudframe, aktuell webbvy, origin, dokument och navigeringsgeneration. JS får inte välja lokala filpaths, läsa urklippet via RPC eller exekvera kommandon. Ett giltigt DOM-element räcker inte som filbehörighet; ett native engångstillstånd måste redan finnas efter en faktisk användarhandling.

Sidans vanliga script kan ändra dess DOM även om vår JS-värld är isolerad. Därför krävs entydig input, dokument-/frame-kontroll och fail-closed uppförande. Det här är inte en formell säkerhetsrevision och inte ett löfte om att en angripen ChatGPT-sida aldrig kan påverka det innehåll användaren själv väljer att skicka.

Top-level chat/auth-hosts valideras exakt. Externa http(s)-länkar öppnas bara efter länkhandling. Detta är **inte** en global CDN-resursblocklista; tjänstens normala nätverksresurser fortsätter användas. Själva inloggningsleverantören kan neka inbäddad webbläsare. Lägg inte till wildcard-hosts eller falsk Chrome-identitet för att kringgå detta.

## Filer och sandbox

Det paketerade appbygget aktiverar App Sandbox, nätverksklient och user-selected read/write. Ingen Full Disk Access, allmän Accessibility, incoming server entitlement, microphone-entitlement eller shell-brygga ingår.

FileURL-representationer läses endast vid uttrycklig paste/drop/file picker. Plaintext `/Users/...` eller `file://...` öppnas inte som lokala filer. Native URL-objekt och säkerhetsscope behålls under handoff. Själva scope-/Finder-beteendet måste provas i den **sandboxade appen**, inte godkännas från en osandboxad XCTest-process.

File promises, mappar/paket och identifierade molnplatshållare stöds inte; de ska ge tydligt fel. Saknar en fil åtkomst stoppas batchen före handoff. Efter handoff styr WebKit/tjänsten uppladdningen; ett lokalt Avbryt får inte kallas serveråterkallelse.

## Lokal lagring

Biblioteket ligger under appens Application Support i dess sandbox när det paketerade bygget körs. JSON och backup skrivs med privata filrättigheter. De är **inte applikationskrypterade**. Filnamn/status kan visas lokalt i panelen. Ingen automatisk chatthistorikarkivering sker.

Automatiska utkast finns enbart i processens begränsade minne, utan automatisk återinsättning. Spara utkast kräver uttrycklig handling. Det förhindrar inte alla möjliga kopplingar mellan samma URL och olika konton; bevisad kontosäker persistent autosave är kvarstående arbete. Spara aldrig känsliga nycklar i promptbiblioteket.

## Diagnostik

Appens explicita diagnostikexport inkluderar teknisk version/OS/arkitektur och antal statusrader, men inga tokens, URLs, filnamn, paths, prompttexter eller bytes. OS-kraschrappporter och byggutdata kan ändå innehålla annan metadata och ska granskas manuellt. Test-fixturens export innehåller namn/hash av de syntetiska filerna.

## Signering

Byggskriptet signerar bara det nya lokala bygget. Ad-hoc är inte Developer ID eller notarisering. En produktrelease kräver separat granskad signerings-/notariseringsprocess. Inga kommandon i projektet tar bort quarantine eller stänger av Gatekeeper. Bygg inte/kör inte med sudo för att kringgå ett misslyckat test.
