# ChatDesk – krav och arbetsinstruktion till Codex
## Version 2: native macOS, låg resursförbrukning och blandade filer via urklipp

Datum: 2026-09-08\
Status: kravunderlag; ingen implementation eller live-kompatibilitet är verifierad.\
Målplattform: användarens faktiska Mac.\
Arbetsnamn: ChatDesk; ingen officiell koppling till OpenAI.

> DETTA DOKUMENT ERSÄTTER ALLA TIDIGARE CHATDESK-SPECIFIKATIONER OCH STARTINSTRUKTIONER.
> Electron är inte längre en kandidat eller reservlösning. Användaren kräver en mycket lätt, snabb och avskalad app.
> Flera olika filtyper via EN kopiera-/klistra-in-operation är ett obligatoriskt P0-krav, inte ett önskemål.

## 1. Uppdrag, ändringar och prioritet

Bygg en separat macOS-app för vanlig ChatGPT-chatt, research och bollplank. Det tunga projektarbetet ska stanna i Codex. Använd det befintliga ChatGPT-kontot genom den riktiga webbtjänsten. Tillför användbara lokala funktioner utan att bygga en tung webbläsare eller ytterligare en agentmiljö.

Användarens senaste besked är auktoritativt:
- Ingen Electron-app eller annan paketerad Chromium-runtime.
- Mycket låg resursförbrukning, snabb respons och ett rent, kompakt gränssnitt.
- Kopiera flera blandade originalfiler tillsammans och klistra in dem som faktiska bilagor. Detta ska fungera lika självklart som vanlig text inklistras.

Tidigare krav på `samuelmaddock/electron-browser-shell`, Electron Forge, Electron/React som appgrund och komplett Chrome-tilläggsladdning är härmed upphävda. Kravet på återanvändning kvarstår bara där koden passar den nya native-arkitekturen utan en tung kompatibilitetsmotor.

Prioritet:
1. Korrekt och säker inloggning samt faktiskt fungerande blandad filinklistrning.
2. Låg total belastning, snabb interaktion, stabilitet och ingen dataförlust.
3. Ett litet och underhållbart native-program, med selektiv kodåteranvändning.
4. Utkast, promptbibliotek och bättre läsning.
5. Ytterligare chattförbättringar först efter godkänd grund.

Stanna inte vid en plan när implementation är möjlig. Bygg däremot inte resten av produkten ovanpå en overifierad inloggning eller filöverföring.

## 2. Bindande teknikval och avgränsningar

### 2.1 Native-teknik

- Swift och AppKit för appens livscykel, huvudfönster, meny, responder chain och native-filhantering.
- Systemets WebKit genom `WKWebView` för den riktiga ChatGPT-webben. Ingen egen distribuerad webbläsarmotor. [S1]
- SwiftUI är tillåtet för mindre inställnings-/hjälppaneler om det förenklar och klarar mätningarna; inte som ursäkt att skapa om webbvy eller laddning vid varje state-ändring.
- `NSPasteboard`/`NSPasteboardItem` och fil-URL:er för native-urklipp. Klassificera med faktiska tillgängliga representationer och vid behov `UniformTypeIdentifiers`.
- `NSOpenPanel` och dokumenterade `WKUIDelegate`-API:er för filval. Respektera filkontrollens faktiska förutsättningar och verifiera överföringen; ett API som accepterar URL:er bevisar inte att webbplatsen accepterar alla filer. [S4, S5]
- `WKDownload` och dokumenterade delegater för nedladdningar där lämpligt.
- Små, versionsmärkta lokala datalager; atomiska skrivningar, begränsad cache och testad migration. Ingen databasplattform utan behov.

En native app betyder här ett native-appskal och native lokala funktioner. Själva ChatGPT-sidan är fortfarande webbteknik. Uppdraget omfattar inte en fristående Swift-återimplementation av hela tjänstens gränssnitt.

### 2.2 Inte tillåtet

Ingen Electron, CEF, QtWebEngine eller annan inbäddad Chromium-distribution. Ingen separat Node/Bun/Deno-runtime, lokal webbserver, Docker, Python-tjänst eller agentprocess i den installerade appen. Byt inte till Tauri, en Chrome-PWA eller annan paketering utan ett nytt uttryckligt teknikbeslut från användaren.

Ingen OpenAI-API-klient, API-nyckel, Codex CLI/SDK, OAuth-proxy, lokal modell, modellrouter, RAG, terminal, repoindexering eller molnsynk i produkten. Ingen egen telemetri eller automatiska AI-anrop.

Ingen cookieimport, sessionstokenextraktion, odokumenterad backendintegration, CAPTCHA-/inloggningsbypass eller avstängda säkerhetskontroller. Vanlig inloggning ska bevisas på riktigt.

Inga automatiskt skickade chattmeddelanden. Inklistrning av bilagor får starta det normala uppladdningsflödet, men appen får inte skicka prompten åt användaren.

## 3. Miljö, befintligt arbete och återanvändning

Inspektera först aktuell arbetskatalog, Git-status, faktisk macOS-version, processor och installerade Swift-/Xcode-verktyg. Anta inte arkitektur från webbläsarens user-agent. Arbeta i en separat lokal gren och skydda befintliga ändringar. Ingen automatisk push eller publicering.

Behov i byggmiljön:
- Git och en stabil Swift-/Xcode-kedja kompatibel med användarens Mac.
- Native macOS app-target med reproducerbart releasebygge. Swift Package Manager för verkligt nödvändiga paket.
- XCTest/Swift Testing för logik; XCUITest och Instruments eller motsvarande Apple-verktyg för faktisk UI-/prestandaverifiering där tillgängligt.
- Node/Bun får finnas ENBART som dokumenterat byggverktyg för en selektivt återanvänd JS-modul. De får inte medfölja appen eller behöva köras av användaren.
- Lokal `.app` och `.dmg` via en liten dokumenterad bygg-/paketeringskedja. Distributionens signering/notarisering redovisas separat och sanningsenligt.

Installera inte systemverktyg, ändra systeminställningar, köp tjänster eller radera befintliga appar utan behörighet. Ett tidigare Electron-utkast får sparas på en separat gren som referens men får inte bli den nya produktens runtime. Avinstallera inte användarens globala Node-/Codex-verktyg.

Återanvänd i första hand små native-byggdelar och plattformsoberoende algoritmer. De tidigare granskade ChatGPT-projekten är kandidater till referensmaterial, inte godkända beroenden. Lås fullständig commit-SHA, licens, återanvända filer och egna patchar i `UPSTREAMS.md` och bevara notices.

`TanChuping/chatgpt-voyager` kan granskas för fristående logik för prompter, utkast, bokmärken och läsning. Det finns inget krav att bära med hela tillägget, React-UI, MV3-service-worker eller en Chrome-API-emulator. Testa faktisk återanvändbarhet, inte bara dess README. En stor portning som skapar en tung app strider mot uppdraget.

## 4. Arkitektur och säkerhetsgräns

Standardläget har ETT huvudfönster och EN laddad ChatGPT-webbvy. Globalt kortkommando återvisar/fokuserar samma fönster. Ingen dold extra snabbchatt eller förladdad vy för varje konversation/projekt. Framtida flerfönsterstöd är behovsstyrt och utanför första versionens krav.

Använd en egen persistent `WKWebsiteDataStore`, isolerad från andra appar och utan importerade sessioner. SDK-/OS-stöd för eventuella profilspecifika API:er måste kontrolleras; använd inte beta-API:er av slentrian. [S7]

Minsta föreslagna moduluppdelning:
- App/fönster/meny/responder chain.
- Webbsession, navigation och normala autentiseringspopupfönster.
- Native `ClipboardReader` och en gemensam `AttachmentCoordinator`.
- Native nedladdningshantering.
- Lokalt utkast-/prompt-/bokmärkeslager.
- En smal, utbytbar webbplatsadapter för de förbättringar som verkligen kräver den.

Dokumenterad scriptkommunikation ska vara starkt begränsad. Validera meddelandetyp, argumentstorlek, avsändande frame/origin, aktuell navigation och användarens aktiva operation. En JSON-validering är inte en behörighetskontroll.

Webbsidan får aldrig kunna ange en godtycklig lokal sökväg, läsa hela urklippet genom ett generellt kommando, starta en shellprocess eller ladda lokal data i bakgrunden. Eventuella filreferenser ska vara opaka, kortlivade och bundna till ett uttryckligt lokalt filval/klistra-in samt rätt konversation.

Behåll WebKits processisolering och normal macOS-säkerhet. WebKit har egna hjälpprocesser; en webbvy är inte en enda OS-process. Mät dem också. [S8]

## 5. P0-CLIP: flera blandade filer via kopiera/klistra in

### 5.1 Exakt användarflöde – första obligatoriska testet

1. I Finder markeras samtidigt sex giltiga, små testfiler: PDF, DOCX, XLSX, PNG, JPG och TXT.
2. Användaren kopierar hela urvalet en gång.
3. Användaren växlar till ChatDesk och fokuserar ChatGPTs vanliga meddelandefält.
4. Användaren klistrar in en gång.
5. ALLA sex originalfilerna ska gå till rätt konversation som faktiska bilagor, en gång per fil, utan att användaren väljer dem på nytt.
6. Befintlig prompttext och redan bifogade filer ska finnas kvar. Meddelandet ska inte skickas automatiskt.

På Mac ska standardflödet använda `Cmd+C` och `Cmd+V`. Detta är samma kopiera-/klistra-in-behov som användaren beskriver som Ctrl+C/Ctrl+V. Menyvalet Redigera → Klistra in och relevant kontextmeny ska nå samma hantering.

Tillhandahåll vid behov en valfri lokal Control+C/Control+V-mappning. Den får bara gälla när appen och relevant fält har fokus, får inte ändra andra appar och ska vara avstängd som standard så att vanliga macOS-tangentbindningar inte kapas. Appen styr inte Finders tangentbindningar.

**Drag-and-drop och filväljare måste också fungera, men ersätter INTE detta test. En app där blandade filer bara går att dra in uppfyller inte användarens krav.**

### 5.2 Läs hela urklippet korrekt

Använd AppKits objekts-/itemmodell. `pasteboardItems` innehåller alla urklippsposter; en bekvämlighetsläsning av `data(forType:)` kan bara ge första matchande post. Implementationen får därför inte begränsas till ett enda item eller en enda datatyp. [S2, S3]

- Identifiera samtliga filposter/file-URL:er från den uttryckliga paste-operationen.
- Ett item kan ha flera representationer, exempelvis filreferens, filnamnstext och förhandsvisning. Skapa INTE tre bilagor av samma fil och välj INTE filnamnstexten eller miniatyren i stället för filen.
- Bevara pasteboard-ordningen så långt den går att fastställa; lova inte Finders visuella ordning om systemet levererar en annan.
- Vanlig text som innehåller `/Users/...` eller `file://...` är inte i sig tillstånd att öppna filen. Kräver faktisk användarvald filrepresentation eller separat filval.
- Läs urklippsinnehåll bara vid användarinitierad paste. Ingen polling, historikinsamling eller bakgrundsbevakning.
- Snapshotta operationens itemmetadata vid start. Om användaren kopierar något annat medan batchen pågår ska den redan startade batchen inte byta innehåll eller få extra filer.
- Testa dokument med mellanslag, åäö, långa namn och lika filnamn från olika kataloger. Två olika filer med samma namn får inte slås ihop.
- Otillgänglig/raderad fil, katalog, behörighetsfel eller ej stödd representation ska få ett tydligt fel, inte förvandlas till tom fil eller filnamnstext.
- Molnplatshållare och file promises från exempelvis mejlprogram ska redovisas separat. De får inte markeras stödda utan källspecifika tester. Hantera den användarvalda filen asynkront om plattformen medger det; skanna inte kontot eller disken.

### 5.3 Bevisa hela kedjan, inte bara den lokala kön

Del A: native-appens kod har identifierat rätt fil-URL:er och behörigheter.\
Del B: den verkliga ChatGPT-kompositorn har tagit emot filerna och genomfört uppladdningen.

Båda krävs. Att visa sex snygga lokala filkort bevisar inte Del B. Att anropa ett JavaScript-`paste`-event bevisar inte heller att inklistrning eller uppladdning har skett; syntetiska clipboard-events gör inte själva en normal system-paste. [S6]

Börja med WebKits normala paste-/filhantering på den faktiska Macen. Om en smal adapter behövs ska den vara dokumenterad, användarstyrd och verifierad mot webbplatsen. Använd bara dokumenterade plattformsgränssnitt och normal tillåten webbinteraktion.

En native bilagekö får ha begränsad intern sekventiell överföring, men användaren ska fortfarande behöva bara EN paste. Ingen extra filväljare eller upprepad manuell uppdelning får döljas bakom ett PASS. Sådana alternativ kan erbjudas som reservväg när testet är FAIL, men uppfyller inte kravet.

Ändra inte MIME-typ till något missvisande, förfalska inte uppladdningskontroller och anropa inte privata upload-endpoints. Kringgå inte tjänstens fil-/konto-/säkerhetsgränser. Om tjänsten eller plattformen inte medger flödet ska det rapporteras som en blockerare; byt inte till Electron för att gömma problemet.

### 5.4 Originalfiler, status och deduplicering

- Bevara originalfilernas bytes, namn och filformat genom VÅR överföringskedja. Ingen konvertering av DOCX/XLSX/PDF till text, PNG eller ZIP. Ingen OCR.
- Separera detta från en rå skärmbild i urklippet, som saknar originalfil: den får materialiseras som en bildfil utan onödig nedskalning. Kopierad JPG/PDF-fil får inte ersättas av sin förhandsvisning.
- Håll filer som referenser tills innehållet faktiskt behövs. Ingen base64-sträng med hela batchen, ingen eager inläsning av alla bytes och inga dubbla fullstora bild-/filkopior i native-minne och JavaScript-minne.
- Begränsa samtidig materialisering/överföring. Frigör bytes, temporärfiler och behörigheter efter avslut/avbrott. UI får inte blockeras av nätverk eller stora filoperationer.
- Bevara originalets URI-behörigheter där plattformen kräver det; utvidga inte appens generella åtkomst för att undvika ett filfel.
- Ge varje paste en operationsidentitet. Native-hanteraren och webbsidans normala paste får inte båda ladda upp samma fil.
- Deduplicera inom en oavsiktligt dubbelhanterad operation, inte enbart på filnamn. En ny medveten paste av samma fil hanteras med en tydlig, testad regel; den får inte silently försvinna.
- Status per fil ska skilja exempelvis `Identifierad lokalt`, `Överförs`, `Bekräftat bifogad`, `Fel`, `Avbruten` och `Status okänd`.
- Visa procent bara där den kan mätas. Ett synligt filnamn eller uteblivet fel är inte ensamt en säker slutbekräftelse.
- Om konversation eller konto ändras mitt i en batch: fortsätt inte till den nya chatten. Pausa/avbryt och visa vad som verkligen skickats till den ursprungliga.
- Ett fel i en fil får inte ge tyst bortfall av resten. Visa delresultat och låt användaren själv välja fortsatt åtgärd utan automatisk omsändning.

### 5.5 Verifiering av riktiga filer

Lokala integrationstester ska använda syntetiska giltiga dokument, en testkompositor/mottagare och hashjämförelse av de mottagna filernas bytes. De ska kunna upptäcka att bara filnamn eller miniatyrer skickas. En lokal fixture-server är tillåten ENBART som testverktyg, inte som produktberoende.

Live-test kräver riktig Finder-kopiering, en riktig tangent-paste och faktiska bilagor i ChatGPT. Användaren ska kunna bekräfta att alla små testfiler är färdigbifogade; innehållsläsning kan provas genom en uttryckligt användarskickad kontrollfråga med ofarliga testmarkörer.

Påstå inte att serverlagrade originalbytes är hashverifierade om bara den lokala kedjan har mätts. Dokumentera exakt vilken del som verifierats. Ingen nätverkstokenavlyssning eller privat backendavläsning som testgenväg.

## 6. Övriga obligatoriska P0-funktioner

### P0-APP: ett riktigt, avskalat Mac-program

Eget appnamn, bundle-ID, Dock-post, Cmd+Tab-post och datakatalog. Behåll befintliga ChatGPT-/Codex-installationer orörda. Sparad fönsterstorlek och position ska fungera även efter skärmbyte. Föreslagen global genväg: Ctrl+Option+Space, konfigurerbar och utan att tyst ta över en befintlig genväg.

Cmd+Q ska avsluta appen; inga egna tjänster ska lämnas kvar. Native-menyer, systemtypsnitt, bra tangentbordsnavigation och läsbara avstånd. Mörkt/ljust efter systemet. Ingen dashboard, dekorativ animation, tung transparens eller alltid synlig sidopanel för varje extrafunktion.

### P0-ACCOUNT: normalt befintligt konto

Riktig ChatGPT-webb, vanlig interaktiv inloggning, relevant MFA och session efter omstart. Behåll webbens modellväljare, reasoning-val, historik och Projects. Hårdkoda inte modellnamn eller försök ge åtkomst kontot saknar.

Testa användarens faktiska inloggningsmetod. Ett externt webbläsarfönster ger inte automatiskt appen samma session. Blockerad inloggning är en verklig blockerare. Normal autentiseringspopup hanteras separat från vanliga externa länkar.

### P0-INPUT: övriga inmatningsvägar

Samma blandade batch ska fungera via Finder-drag och multi-filval, med samma fel-/statusregler som paste. `WKOpenPanelParameters.allowsMultipleSelection` beskriver webbkontrollens stöd; att visa en panel med multival garanterar inte korrekt överföring till en single-file-kontroll. [S4, S5]

Vanlig Cmd+V för text, flerradig kod, Unicode, skärmbild och bild ska fungera utan att filadaptern tar över fel operation. Cmd+C från markerad svarstext och kod ska fungera mot andra appar. Redigering i ett lokalt sök-/namnfält ska inte bifoga filer till chatten av misstag.

### P0-DOWNLOAD: fungerande filer ut

Spara användarinitierade PDF-/DOCX-/XLSX-/bildnedladdningar och visa platsen i Finder. Testa faktiska autentiserade/blob-flöden där tjänsten använder dem. Tydlig status, avbrott och namnkonflikt; inga tysta överskrivningar eller automatiskt öppnade körbara filer.

### P0-RECOVERY: stabilitet och bakgrund

Att dölja appen eller växla till Codex får inte avsiktligt avbryta ett pågående svar eller en filöverföring. Undvik permanenta wake locks, avstängd App Nap och globalt ändrad bakgrundspolicy. Testa faktiskt beteende i WebKit och redovisa vad som inte kan garanteras. Fortsatt arbete under riktig systemvila utlovas inte.

Hantera nätverksfel, uppvakning och WebContent-krasch utan automatisk omsändning. Bevara synlig felstatus och möjlighet till kontrollerad reload; inga oändliga reload-loopar.

### P0-VALUE: faktiska men lätta förbättringar

Efter godkända grundprov: textutkast per konversation, ett litet sökbart promptbibliotek, justerbar läsbredd/textstorlek och förbättrat scrollbeteende. Håll dessa moduler små och individuellt avstängningsbara. Globala genvägen visar samma webbvy, inte en ny dold instans.

Spara utkast debouncerat och atomiskt. Isolera per profil, konto/arbetsyta och konversation. Osäker identitet får inte leda till automatisk återinfogning. Skriv inte över nytt innehåll med ett gammalt utkast. Bilagor får inte påstås återställda efter omstart om de behöver väljas igen.

Tillfälliga chattar får inte få bestående utkast eller automatisk lokal arkivering som standard. Promptinfogning skickar aldrig texten automatiskt.

### P0-SAFE: felsäkert läge

Starta grundchatten utan egna webbplatsförbättringar utan att radera session eller lokala data. Native filfunktioner och webbplatsadapter ska kunna diagnostiseras var för sig. Ett trasigt tillägg får inte blockera modellväljare eller normal textinmatning.

## 7. Mätbara krav på liten och snabb app

### 7.1 Metod

Mät ett installerat RELEASE-bygge på användarens Mac. Redovisa maskin, macOS, SDK, arkitektur, appversion, läge, antal körningar, nätverk och om OS-cacher är varma. Ingen jämförelse av debugbygge med optimerad release.

Jämför:
- A: samma native-app med ChatGPT och egna extrafunktioner avstängda.
- B: samma native-app med de avsedda P0-funktionerna aktiverade.
- C: samma innehåll i Safari, när jämförbart, som extra referens – inte ett sätt att dölja A:s grundkostnad.

Redovisa total belastning för native-app + identifierade WebContent-/nätverks-/GPU-hjälpprocesser, och hur processerna kopplats till appen. Räkna inte alla WebKit-processer på datorn som våra. Summerad RSS kan dubbelräkna delat minne; beskriv måttet och använd konsekvent metod. JS-heap eller bara huvudprocessens RAM är inte hela appens kostnad. [S8]

### 7.2 Initiala godkännandebudgetar

Detta är projektmål, INTE redan uppmätta värden eller allmänna garantier för WebKit. Överträdelse ska rapporteras; Codex får inte sänka gränser i tysthet.

| Mätning | Mål för första release |
|---|---|
| Paketerad `.app`, en testad arkitektur, exklusive separat dSYM | högst 30 MiB installerad storlek; alla medföljande bibliotek/script räknas |
| Visa/fokusera redan igångvarande app | p95 högst 150 ms, minst 20 aktiveringar |
| Första synliga lokala fönster vid ny processstart | p95 högst 1 sekund, minst 10 starter; webbens nätverkstid separat |
| Extra stabiliserat minne för B jämfört med A | högst 30 MiB vid stilla normal chatt; samma mätmetod/processomfång |
| Extra CPU för B jämfört med A | högst 0,5 procentenhet av en logisk kärna i medel över 5 minuter i tomgång |
| Lokalt kvitto/filkö efter paste av sex små lokalt tillgängliga filer | p95 högst 150 ms i kontrollerat test; OS-behörighetsdialog och nätverksuppladdning mäts separat |
| Egna återkommande långkörande uppgifter på UI-/webbhuvudtråd | inga återkommande uppgifter över 50 ms i representativa tester |
| 20 upprepade navigerings-/panelcykler | ingen stadig växande minneskurva; skillnad över 30 MiB efter stabilisering utreds som regression |

Redovisa också TOTAL minnes- och CPU-förbrukning: tom start, normal chatt, lång chatt, pågående svar, blandad filinklistrning och dolt läge. Visa appens absoluta kostnad, inte bara B–A. Ange totalbudget för användarens maskin efter grundmätningen, med motivering; anta inte att en full ChatGPT-webbsida ryms i exempelvis 100 MB.

Native-tekniken tar bort kravet att leverera Chromium men bevisar inte låg total RAM-användning. En oacceptabel grundkostnad eller blockerad paste får inte markeras godkänd enbart för att extrakoden är liten.

### 7.3 Byggregler

En laddad webbvy. Hjälppaneler byggs först när de öppnas. Ingen kontinuerlig urklippsläsning, full DOM-genomsökning per token, bakgrundsindexering, periodiska AI-anrop eller stora animerade gränssnitt.

Observera smalt, batcha uppdateringar, koppla bort observers/timers på navigering och ge cache fasta gränser. Håll minnet begränsat även under upprepade paste-/avbryt-operationer. Importera inte hela export-/diagrammotorer för ett promptbibliotek.

Kör tung I/O och förberedelse utanför UI-tråden med backpressure och avbrottsstöd. Använd plattformens säkra processmodell; stäng inte av isolering eller hårdvaruacceleration bara för att ett enskilt minnesmått ser lägre ut.

## 8. Integritet och tillåten interaktion

Respektera normal App Sandbox och snäva filbehörigheter. Kräv inte Full Disk Access, Accessibility-automation av andra appar eller globala keyloggers för vanlig paste. Använd OS-behörighetsflöden där det behövs; om zero-reselect-paste inte kan genomföras säkert ska det vara ett redovisat hinder.

Inga lösenord, cookies, tokens, fullständiga lokala sökvägar, prompttexter eller filinnehåll i standardloggar. Teknisk loggning av itemantal/typer/status kan användas utan att exponera innehållet. Tillåt en avsiktligt användarinitierad, redigerad diagnostikexport.

Ingen automatisk hämtning eller kopiering av all historik. Lokala prompter, egna anteckningar och bokmärken ska vara raderbara. Appen får inte ange att allt är lokalt: ChatGPT och uppladdade bilagor använder tjänsten som vanligt; våra tillägg ska inte skicka data till fler parter.

Ladda endast versionslåsta, granskade lokala adaptermoduler. Webbsidans normala resurser kommer fortsatt från tjänsten. Separera kontroll av top-level-navigation från resursladdning. Externa länkar öppnas i standardwebbläsaren; otillåtna protokoll och lokala filvägar nekas.

Behåll och verifiera licenser för återanvänd kod. Det här dokumentet ger inte tillstånd att ta bort tillskrivningar, kringgå källkods-/licensvillkor eller publicera användarens projekt.

## 9. Fas 0: bevisa native + blandad paste innan utbyggnad

1. Inventera miljö och befintligt repo; dokumentera att Electron-beslutet är ersatt.
2. Bygg en minimal körbar AppKit/WKWebView-app och ett native paste-test utan stor extrafunktionalitet.
3. Testa hela pasteboard-batchen mot lokal fixture/mottagare med verkliga originalfiler.
4. Testa normal manuell inloggning i riktig ChatGPT och session efter omstart.
5. Kör det exakta Finder → Cmd+C → ChatDesk → Cmd+V-testet med sex blandade filer. Verifiera native och verklig webböverföring var för sig.
6. Testa screenshot-paste, vanlig text, Finder-drag, filväljare, en nedladdning och dolt fönster under pågående aktivitet.
7. Mät grundkostnad, fönsteraktivering, filkörespons och minnesbeteende. Dokumentera GO/NO-GO.

När användarens inloggning eller interaktion saknas: leverera en körbar prototyp, exakta teststeg och `BLOCKED/EJ KÖRT`. Fortsätt gärna fristående tester, men markera inte live-krav som PASS och bygg inte hela P1 som om risken är löst.

Om paste eller inloggning blockeras av WebKit/tjänsten: visa exakt vilket steg och vilka offentliga gränssnitt som provats. Ingen Electron-fallback, API-klient, serverproxy eller fake-upload får ersätta kravet. Leverera uppnått resultat och stopporsak.

## 10. Acceptansmatris

`PASS-live`, `PASS-fixture`, `FAIL`, `BLOCKED` och `EJ KÖRT` ska hållas isär. Ett fixture-PASS är inte live-PASS. Använd syntetiska, giltiga dokument; inte SAP-kundmaterial.

| ID | Scenario | Obligatoriskt utfall |
|---|---|---|
| N01 | Inspektera installerad app och runtime | Native Swift/AppKit/WKWebView, ingen Electron/Chromium/Node-server |
| N02 | Start, Dock, Cmd+Tab, genväg och quit | Egen app, samma webbvy återanvänds, inga egna bakgrundstjänster |
| A01 | Verklig inloggning och omstart | Normal session, ingen cookieimport/bypass |
| A02 | Modellväljare, reasoning, historik och Projects | Riktig webb-UI fungerar utan hårdkodad ersättare |
| C01 | Finder-kopiera PDF+DOCX+XLSX+PNG+JPG+TXT, en Cmd+V | Alla sex verkliga bilagor, ingen omselektion, ingen autosändning |
| C02 | Samma batch via Redigera → Klistra in | Samma utfall som C01 |
| C03 | Två filer av samma typ samt flera andra typer | Inte bara första item eller första typen överförs |
| C04 | Fil med fil-URL, namn och miniatyr som representationer | En originalfil, inte namn/thumbnail/dubbletter |
| C05 | Paste när prompttext och bilaga redan finns | Inget innehåll försvinner; tillägg sker en gång |
| C06 | Två olika filer med samma namn och Unicode-namn | Båda identiteter bevaras; inga tysta namnfel |
| C07 | Dubbla event/ny avsiktlig paste | En operation dubbelhanteras inte; nästa hanteras enligt synlig regel |
| C08 | Saknad/otillgänglig/otillåten fil i batch | Tydliga individuella fel och delresultat, inga tomma ersättningar |
| C09 | Konto-/chattbyte under batch | Ingen bilaga hamnar i ny/fel konversation |
| C10 | Ändra systemurklippet under pågående batch | Den startade operationen byter inte innehåll |
| C11 | Verklig screenshot i urklipp och kopierad JPG-fil | Råbild hanteras, originalfil ersätts inte av preview |
| C12 | Text, kod, åäö, radbrytningar; kopiera svar ut | Normal redigering fungerar utan felaktig bilagehantering |
| C13 | Paste i lokalt sök-/namnfält | Ingen oavsiktlig uppladdning till chatten |
| C14 | Lokal mottagare och hash av sex originalfiler | Byte-identisk lokal överföring; ingen ZIP/text/OCR-genväg |
| C15 | Riktig webböverföring efter C01 | Bekräftade faktiska bilagor, inte bara lokal kö/fake-event |
| F01 | Samma batch via Finder-drag | Alla bilagor en gång, originalformat |
| F02 | Samma batch via filväljare | Alla bilagor en gång; stöd bedöms separat från C01 |
| F03 | Filer ut, avbrott, namnkonflikt och Visa i Finder | Verkliga sparade filer, säker hantering |
| R01 | Dölja app, växla till Codex, nätverksfel, vila/uppvakning | Ingen avsiktlig förlust eller automatisk dubbelsändning |
| R02 | Utkast vid reload/krasch/chatt-/kontobyte | Rätt utkast, inget överskrivet nytt innehåll eller identitetsläckage |
| R03 | Tillfällig chatt | Ingen automatisk bestående utkastssparning |
| R04 | Adapterfel och felsäkert läge | Grundchatten fungerar, inga raderade sessioner |
| S01 | Fientligt scriptmeddelande, path-sträng och fel origin | Ingen åtkomst till godtycklig fil/urklipp/shell |
| P01 | Mät appstorlek, start, aktivering och B–A | Faktiska releasevärden och total belastning redovisas |
| P02 | Lång chatt, paste av större filer, 20 cykler | Respons bibehålls, begränsat filminne, ingen stadig läcka |

Källspecifik paste från exempelvis Outlook, iCloud Drive och externa volymer kan läggas till när sådana källor finns tillgängliga. De ska inte antydas vara verifierade av Finder-testet. Kontrollera verkliga OS-/webbbehörigheter; fixtures ersätter dem inte.

## 11. Fortsatt utveckling och leverans

Efter godkänd Fas 0 implementeras resterande P0. P1 omfattar sedan, i liten omfattning: lokala bokmärken/anteckningar/återkom-markeringar, navigering i långa chattar, lokala mappar, användarinitierad export av tillgängligt innehåll och valfri färdigavisering utan privat svarstext.

Avancerad diagramrendering, flera konton, röst och flerfönsterstöd ingår inte i första leveransen. Ingen större produkt än nödvändigt.

Leverera:
- Byggbar native-kodbas och spårbar återanvändning med licenser/notices.
- `AGENTS.md`, `ARCHITECTURE.md`, `UPSTREAMS.md` och `STATUS.md` med exakt nästa steg.
- `CLIPBOARD_TESTS.md` med inputrepresentationer, filantal, kopplingsmetod, verkligt slutresultat och testomfång.
- `TEST_REPORT.md` med live/fixture och PASS/FAIL/BLOCKED/EJ KÖRT.
- `PERFORMANCE.md` med mätmetod, A/B-jämförelse, absoluta totalvärden och budgetavvikelser.
- En installerbar lokal `.app` och `.dmg` för verifierad arkitektur, med ärlig signeringsstatus.
- Enkla dokumenterade kommandon för bygge, tester, profilering och paketering; ingen terminal behövs vid normal användning.
- Backup/migration/felsäkert läge samt kort användar- och avinstallationsguide. Uppdatera adaptermoduler kontrollerat; dokumentera även beroendet av macOS system-WebKit.

En kompilerande Swift-app är inte en färdig leverans. **Blandad filinklistrning måste vara live-verifierad. Drag-and-drop ensamt räcker inte. Native teknik utan faktisk prestandamätning räcker inte heller.**

## 12. Primärkällor och tekniska begränsningar

Källorna verifierades vid kravuppdateringen. Kontrollera faktisk SDK-/OS-tillgänglighet vid bygget. De dokumenterar byggdelar och gränser, inte färdig ChatGPT-kompatibilitet.

- [S1] Apple: WKWebView och native-vy/delegater: https://developer.apple.com/documentation/webkit/wkwebview/
- [S2] Apple: NSPasteboard, objektläsning och skillnaden mellan alla items och första matchande data: https://developer.apple.com/documentation/appkit/nspasteboard/index(of:)
- [S3] Apple: canReadObject(forClasses:options:), fil-URL-/typalternativ och hänvisning till readObjects: https://developer.apple.com/documentation/appkit/nspasteboard/canreadobject(forclasses:options:)
- [S4] Apple: WKUIDelegate filuppladdningspanel med URL-lista: https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:runopenpanelwith:initiatedbyframe:completionhandler:)
- [S5] Apple: WKOpenPanelParameters.allowsMultipleSelection: https://developer.apple.com/documentation/webkit/wkopenpanelparameters/allowsmultipleselection
- [S6] W3C: Clipboard API and events, särskilt begränsningen hos syntetiska clipboard-events: https://www.w3.org/TR/clipboard-apis/
- [S7] WebKit: persistenta profildatalager och OS-gränser: https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/
- [S8] WebKit: processmodell: https://webkit.org/debugging-webkit/
- [S9] WebKit: Async Clipboard API, användargester och flera representationer; historisk API-artikel, inte en aktuell komplett MIME-kompatibilitetsmatris: https://webkit.org/blog/10855/async-clipboard-api/

## 13. Startorder till Codex

Läs hela dokumentet. Uppdatera gamla Electron-beslut och statusdokument utan att förstöra befintligt arbete. Bygg nu en liten native Swift/AppKit/WKWebView-prototyp. Börja med native clipboard-läsning av hela Finder-batchen, normal inloggning och faktisk överföring till ChatGPT. Mät releasebygget. Gör bara därefter utkast, promptbibliotek och övriga förbättringar.

Redovisa blockerade tester ärligt. Ingen Electron-fallback och inget byte från kopiera/klistra in till enbart dra och släpp. Slutrapporten måste visa vilket bevis som finns för vart och ett av de två viktigaste kraven: låg faktisk resursförbrukning och blandade originalfiler via en paste.
