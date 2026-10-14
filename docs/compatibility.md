# Compatibilità con WoW Forever

Stato: **capability verificate** sul client (spec §3). Il rilascio resta
chiuso finché la checklist manuale (`docs/manual-tests.md`) non è completa.

<!-- compat: filterApi=true payload=true lineId=true eventFrame=true -->
<!-- release-gate: closed -->

I due commenti sopra sono letti da `tests/test_adapter.lua` e da
`scripts/release.py check-gate`. Ogni flag deve coincidere con
`Adapter.COMPAT.verified` in `ForeverChatGuard/Adapters/Forever.lua`, e va
portato a `true` solo insieme all'evidenza registrata in questo file.

## Sessioni di verifica

| Data | Build | Metodo | Esecutore |
| --- | --- | --- | --- |
| 2026-10-14 (1) | 1.60.1.70374 (`GetBuildInfo`, compilata il 12 ottobre 2026) | Probe `tools/ForeverChatGuardProbe` 0.1.0 + ChatGuard 0.1.0-alpha.1 in osservazione, realm `Classic Beta PvE`, personaggio di livello 10, fuori istanza, client enUS | proprietario del progetto; file `ForeverChatGuardProbe.lua` e screenshot del pannello |
| 2026-10-14 (2) | 1.60.1.70374 | Stesso setup + test guidato `/fcgprobe auto` nel canale privato `fcgprobetest` con una seconda finestra chat «Probe»; messaggi reali di altri giocatori in General - Elwynn Forest | proprietario del progetto; `ForeverChatGuardProbe.lua` (load 4) e screenshot `probe_debug` |

## Target

| Voce | Valore | Stato | Evidenza |
| --- | --- | --- | --- |
| Prodotto | WoW Forever, client beta `wow_classic_beta` | verificato | `.build.info`; probe: `WOW_PROJECT_ID` 18 |
| Build client | 1.60.1.70374 | verificato | Probe 2026-10-14 (la build 70338 letta prima in `.build.info` è stata aggiornata) |
| Interface TOC | `16001` | verificato | Probe: `GetBuildInfo()` → 16001; entrambi gli addon caricati con quel valore |
| Runtime Lua | Lua 5.1: niente `goto`, `//`, operatori bitwise; libreria `bit` presente, `utf8` assente | verificato | Probe `lua` |
| Restrizioni addon | stati `C_RestrictedActions` 0–5 tutti `false` al login e durante i messaggi | verificato fuori istanza | Probe `restrictionsAtLoad`, `samples[].restrictions` |
| Restrizioni combattimento | combat log vietato; HP/potere secret | verificato da HC One Button | `hc-one-button/docs/FOREVER_FEASIBILITY.md` |

## Capability chat

| Capability | Flag | Stato | Evidenza / limite |
| --- | --- | --- | --- |
| Filtro messaggi | `filterApi` | **verificato** | `ChatFrame_AddMessageEventFilter`/`Remove...` e `ChatFrameUtil.AddMessageEventFilter`/`Remove...` presenti. Registrazione su `CHAT_MSG_CHANNEL`, `SAY`, `YELL` → `ok`, nessun `ADDON_ACTION_FORBIDDEN/BLOCKED`. `return true` nasconde la riga (`fcgprobe-hide tre` assente in Say e nel canale, in entrambe le finestre); `return false` senza altri valori lascia le righe visibili e invariate |
| Payload `CHAT_MSG_SAY` | `payload` | **verificato** | 18 argomenti. 1 testo `string`; 2 autore `string` **senza reame, con uno spazio** (nome + cognome); 5 autore ripetuto; 7 zoneChannelID `0`; 8 `0`; 9 `""`; 10 languageID; 11 lineID `number`; 12 GUID `Player-…`; 13 `number`; 14–17 `boolean`; 18 `table` |
| Payload `CHAT_MSG_CHANNEL` | `payload` | **verificato** | Messaggi di altri giocatori in General: testo e autore non secret, autore senza reame; 4 nome numerato del canale; 7 zoneChannelID `1`; 8 indice canale `1`; 9 channelBaseName `General - Elwynn Forest` (contiene la zona: per questo la chiave usa zoneChannelID); 11 lineID |
| Payload `CHAT_MSG_YELL` | — | non verificato | Stesso gestore di Say nel client; non catturato |
| Identità consegna (`lineID`) | `lineId` | **verificato** | Unico per messaggio (anche per testi identici). Il filtro viene chiamato **una volta per ogni chat frame registrato (10, anche nascosti) con lo stesso `lineID`**; `frameEvents = 1`. Da qui la cache decisioni per `evento:lineID` |
| Consegna a frame addon | `eventFrame` | **verificato** | Un `OnEvent` per messaggio |
| Chiave canale | — | **verificata** | La chiave da `C_ChatInfo.GetChannelInfoFromIdentifier` (`zone:1` per General) coincide con quella derivata dai messaggi; canale privato `custom:fcgprobetest` selezionato per nome e analizzato |
| Valori secret nella chat | — | assenti fuori istanza | Nessun argomento secret in 5 campioni. Istanze/encounter non provati |
| API canali | — | **verificate per l'uso fatto** | `GetChannelList` + `C_ChatInfo.GetChannelInfoFromIdentifier` restituiscono i canali entrati con `zoneChannelID`; l'adapter mantiene i controlli di tipo |
| Template UI | — | **verificato** | `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`, `BasicFrameTemplateWithInset`, `BackdropTemplate` creati senza errori |
| Slash command, SavedVariables | — | **verificato** | `/fcg` e `/fcgprobe` risposti; `ForeverChatGuard.lua` e `ForeverChatGuardProbe.lua` scritti dal client in `WTF\Account\<account>\SavedVariables\` |
| Altre API | — | presenti | `issecretvalue`, `canaccessvalue`, `canaccesstable`, `GetTime`, `GetTimePreciseSec`, `UnitName`, `UnitGUID`, `GetNormalizedRealmName`, `C_Timer`, `Settings`, `UISpecialFrames`, `InCombatLockdown`, `date` |

Legenda: **verificato** = osservato sul client target con il metodo indicato;
**assente** = cercato e non trovato; **non verificato** = non ancora provato.
I test offline usano mock e non sono prova di compatibilità.

## Correzioni nate dalla verifica

- Nomi autore con spazio (nome + cognome) accettati; chiave `Nome Cognome-Reame`
  (prima venivano rifiutati e ogni messaggio risultava non analizzabile).
- Layout del pannello ricostruito (allineamento, testo dentro la cornice,
  canali selezionabili con checkbox); controllato da `tests/test_panel.lua`.
- Il probe creava un `EditBox` visibile che catturava la tastiera: ora i
  widget di prova sono nascosti; test statico su `SetAutoFocus(false)`.

## Comportamento attuale

- Osservazione via frame eventi sui canali selezionati (primo avvio).
- `/fcg filter` disponibile: filtro registrato, decisione unica per
  `evento:lineID` in tutte le finestre, regole duplicati/raffiche attive.
- Valori secret: messaggio ignorato, contatore `unreadable`, nessun errore.

## Prima della release

- Completare `docs/manual-tests.md` (in particolare: modalità filtro reale,
  cambio zona, reload/logout, pannello in combattimento, altro addon chat).
- Facoltativo: un messaggio in un'istanza per verificare i valori secret.
- Poi portare il marcatore `release-gate` in testa al file da `closed` a `open`.

## Limiti noti

- Beta mobile: ripetere il probe a ogni build importante.
- Dove gli argomenti sono secret la chat resta invariata.
- Nessuna compatibilità dichiarata con altri addon chat finché non provata.
