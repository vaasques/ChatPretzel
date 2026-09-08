# Prestanda — inga mätvärden finns ännu

Koden innehåller inga påhittade RAM-/CPU-resultat. Linux-kompilering av kärnan eller liten ZIP-storlek säger inget om total Mac-belastning med en verklig ChatGPT-sida.

## Bindande initiala budgetar

| Mätning | Budget |
|---|---|
| Installerad release-`.app`, aktuell arkitektur, inklusive alla resurser | ≤ 30 MiB; exkludera endast separat dSYM. |
| Återvisa igångvarande fönster, minst 20 mätningar | p95 ≤ 150 ms. |
| Ny process till första lokala synliga fönster, minst 10 starter | p95 ≤ 1 sekund; nätverk/sidrendering redovisas separat. |
| Extra minne för förbättringar B–A, stabiliserad normal chatt | ≤ 30 MiB. |
| Extra CPU för B–A, fem minuters tomgång | ≤ 0,5 procentenhet av en logisk kärna. |
| Lokalt kvitto efter paste av sex små tillgängliga original | p95 ≤ 150 ms, behörighetsdialog/nätverk separat. |
| Egna återkommande långa huvudtrådsuppgifter | Inga återkommande uppgifter > 50 ms. |
| 20 navigation-/panelcykler efter stabilisering | Ingen stadig ökning; > 30 MiB regression utreds. |

## Reproducerbar metod på användarens Mac

Dokumentera modell/CPU, macOS/WebKit-version, nätverk, SDK, releasekonfiguration, bygg-ID och exakt samtals-/filscenario. Mät A = samma app med extra funktioner av, B = normalt läge med extrafunktioner. Använd samma chatt, samma zoom och samma originalfiler. Ett kort kallt test och ett varmt test är olika mätningar.

Använd Instruments och macOS processträd/Activity Monitor för att identifiera **appens** WebKit WebContent/Networking/GPU-processer. Rapportera identifierade processer och metod. Addera inte slentrianmässigt delade RSS-sidor och kalla summan exakt fysisk RAM. Blanda inte andra Safari-/WebKit-appars processer med ChatDesk. Dokumentera begränsningen om processattribuering är osäker.

Mät absoluta värden för tom app, normal chatt, lång chatt, strömmande svar, paste, nedladdning och dolt läge. `Hjälp → Exportera diagnostik` mäter inte detta automatiskt och hävdar inte det heller.

Det finns avsiktligt ingen global förbudsbypass för App Nap eller evig process assertion. Testa faktiskt viloläge/återupptagning och lång servergenerering separat innan bakgrundsfunktion lovas.

## Hur implementationen begränsar kostnaden

Ett huvud-WKWebView; native paneler byggs vid behov. Ingen periodisk urklippsläsning, DOM-polling eller helhistorik-indexering. Adaptern har små input/click-lyssnare, en kort debounce för utkast och endast on-demand selector-sökning. Ingen filbytes/base64-kopia genom Swift/JS för upload. Serial disk/file-I/O och fasta gränser för bibliotek, sessionsutkast, transferhistorik och samtidiga operationer.

Detta är designval, inte ett bevis för uppfyllda budgetar. Prioritera root cause vid för hög kostnad, inte avstängning av skydd eller felaktig processredovisning.
