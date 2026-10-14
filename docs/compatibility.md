# Compatibilità con WoW Forever

Stato: **integrazione non verificata**. Il gate del client (spec §3) non è
superato: nessuna release installabile può essere pubblicata.

<!-- compat: filterApi=false payload=false lineId=false eventFrame=false -->
<!-- release-gate: closed -->

I due commenti sopra sono letti da `tests/test_adapter.lua` e da
`scripts/release.py check-gate`. Ogni flag deve coincidere con
`Adapter.COMPAT.verified` in `ForeverChatGuard/Adapters/Forever.lua`, e va
portato a `true` solo insieme all'evidenza registrata in questo file.

## Target

| Voce | Valore | Stato | Evidenza |
| --- | --- | --- | --- |
| Prodotto | WoW Forever, client beta `wow_classic_beta` | verificato (installazione) | `World of Warcraft\.build.info`: Product `wow_classic_beta`, Version `1.60.1.70338`, branch `eu` (letto il 2026-10-14) |
| Identità "Forever" | game type Forever nel client beta | indiziato, non verificato da ChatGuard | Analisi HC One Button `docs/FOREVER_FEASIBILITY.md` (2026-10-13): stringhe `Forever`, `C_GameRules.SetForeverExperiencePreset` nel binario `WowB.exe` |
| Realm usato in beta | `Classic Beta PvE`, realm build 1.60.1.70249 | verificato (log) | `_classic_beta_\Logs\General.log` del 2026-10-13 |
| Build client | 1.60.1.70338 | verificato (installazione) | `.build.info` |
| Interface TOC | `16001` | verificato da un altro addon sulla stessa build | Probe HC One Button eseguito in gioco su 1.60.1.70338 il 2026-10-13: Interface `16001`, `WOW_PROJECT_ID` 18, addon di terze parti caricati |
| Runtime Lua | presumibilmente 5.1 (motore moderno) | non verificato | Il probe ChatGuard registra `_VERSION`, `goto`, `//`, operatori bitwise |
| Restrizioni addon | combat log vietato; HP/potere secret anche fuori combattimento | verificato da HC One Button | `docs/FOREVER_FEASIBILITY.md` (HC One Button), sezione "Esito" |

## Capability chat

| Capability | Flag | Stato | Note |
| --- | --- | --- | --- |
| Filtro messaggi chat (`ChatFrame_AddMessageEventFilter` o `ChatFrameUtil.AddMessageEventFilter`) | `filterApi` | non verificato | Candidati rilevati a runtime. Serve: esistenza, firma, `true` nasconde in tutte le finestre, `false` senza altri valori preserva gli argomenti, nessun `ADDON_ACTION_FORBIDDEN` |
| Payload `CHAT_MSG_CHANNEL/SAY/YELL` | `payload` | non verificato | Layout candidato (client moderni): 1 text, 2 author "Nome-Reame", 7 zoneChannelID, 9 channelBaseName, 11 lineID, 12 GUID. **Rischio principale:** con lo stack Midnight il testo può essere *secret*; in quel caso ChatGuard non può analizzarlo |
| Identità consegna (`lineID`) | `lineId` | non verificato | Deve essere unica per messaggio nella sessione e identica in tutte le callback delle finestre chat. Senza, in modalità filtro le regole duplicati/raffiche restano disattivate |
| Consegna evento a frame addon (`RegisterEvent`) | `eventFrame` | non verificato | Percorso di sola osservazione: un `OnEvent` per evento, contabilità esatta anche senza `lineID` |
| Identità canale | — | non verificato | Chiave `zone:<zoneChannelID>` o `custom:<nome base>`; mai il numero visibile |
| Messaggi propri | — | non verificato | `UnitName("player")` + `GetNormalizedRealmName()` o GUID |
| Slash command, SavedVariables | — | non verificato | Il probe verifica la persistenza (`loads` incrementa dopo `/reload`) |
| Template UI (`UIPanelButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`, `BasicFrameTemplateWithInset`) | — | non verificato | Il pannello degrada a output testuale se manca un template |

Legenda: **verificato** = osservato sul client target con il metodo indicato;
**assente** = cercato e non trovato; **non verificato** = non ancora provato.
I test offline usano mock e non sono prova di compatibilità.

## Comportamento attuale senza verifica

- Filtro: **mai registrato**. `/fcg filter` viene rifiutato con spiegazione.
- Osservazione: se `CreateFrame` esiste, ChatGuard osserva via frame eventi
  dei soli canali selezionati (nessuno al primo avvio). Nulla viene nascosto.
- Valori secret: messaggio ignorato, contatore `unreadable`, nessun errore.
- Etichetta di stato in gioco: «integrazione non verificata».

## Come superare il gate

1. Copiare `tools/ForeverChatGuardProbe/` in
   `World of Warcraft\_classic_beta_\Interface\AddOns\` (senza ChatGuard attivo).
2. Entrare con un personaggio, `/join fcgprobetest` (canale privato, nessuno spam).
3. Nel canale privato inviare: `fcgprobe-pass uno`, poi due volte
   `fcgprobe-pass due` (testo identico), poi `fcgprobe-hide tre`.
   Annotare: le righe `pass` sono visibili e invariate in ogni finestra chat?
   La riga `hide` è assente in tutte le finestre?
4. Aprire una seconda finestra chat che mostri lo stesso canale e ripetere.
5. Facoltativo: lo stesso in un'istanza (dungeon) per rilevare valori secret.
6. `/fcgprobe` per il riepilogo, poi `/reload` (scrive il file) e `/fcgprobe`
   ancora (deve risultare `loads 2`).
7. Fornire `WTF\Account\<account>\SavedVariables\ForeverChatGuardProbe.lua`:
   contiene solo tipi, flag secret, lunghezze e ID numerici, nessun testo o nome.

Con i risultati si compila la tabella sopra (data, build, metodo), si
aggiornano i flag in entrambi i punti e il pannello mostrerà «verificata».

## Limiti noti

- Beta mobile: API e restrizioni possono cambiare a ogni build; ripetere il
  probe a ogni build importante e aggiornare questa pagina.
- Anche con il filtro verificato, ChatGuard non può analizzare messaggi i cui
  argomenti siano secret: in quei contesti la chat resta invariata.
- Nessuna compatibilità dichiarata con altri addon chat finché non provata
  (checklist manuale, voce 11).
