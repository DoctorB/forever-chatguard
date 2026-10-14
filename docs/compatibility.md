# Compatibilità con WoW Forever

Stato: **integrazione parzialmente verificata**. Il gate del client (spec §3)
non è ancora superato: nessuna release installabile può essere pubblicata.

<!-- compat: filterApi=true payload=false lineId=false eventFrame=true -->
<!-- release-gate: closed -->

I due commenti sopra sono letti da `tests/test_adapter.lua` e da
`scripts/release.py check-gate`. Ogni flag deve coincidere con
`Adapter.COMPAT.verified` in `ForeverChatGuard/Adapters/Forever.lua`, e va
portato a `true` solo insieme all'evidenza registrata in questo file.

## Sessioni di verifica

| Data | Build | Metodo | Esecutore |
| --- | --- | --- | --- |
| 2026-10-14 | 1.60.1.70374 (`GetBuildInfo`, compilata il 12 ottobre 2026) | Probe `tools/ForeverChatGuardProbe` 0.1.0 + ChatGuard 0.1.0-alpha.1 in osservazione, realm `Classic Beta PvE`, personaggio di livello 10, fuori istanza, client enUS | proprietario del progetto; file `ForeverChatGuardProbe.lua` e screenshot del pannello letti da ChatGuard |

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
| Filtro messaggi | `filterApi` | **verificato** (Say, una finestra) | `ChatFrame_AddMessageEventFilter`/`Remove...` e `ChatFrameUtil.AddMessageEventFilter`/`Remove...` presenti. Registrazione su `CHAT_MSG_CHANNEL`, `SAY`, `YELL` → `ok`, nessun `ADDON_ACTION_FORBIDDEN/BLOCKED`. `return true` ha nascosto `fcgprobe-hide tre` (assente nella chat dello screenshot); `return false` senza altri valori ha lasciato visibili e invariate le righe `fcgprobe-pass` |
| Payload `CHAT_MSG_SAY` | `payload` (parziale) | verificato | 18 argomenti. 1 testo `string` non secret; 2 autore `string` non secret, **senza reame e con uno spazio** (nome + cognome, es. `Uorriora Uorrior`); 5 autore ripetuto; 7 zoneChannelID `0`; 8 `0`; 9 `""`; 10 languageID `7`; 11 lineID `number`; 12 GUID `Player-…`; 13 `number`; 14–17 `boolean`; 18 `table` |
| Payload `CHAT_MSG_CHANNEL` | `payload` | **non verificato** | Nessun messaggio di canale catturato: i messaggi di prova sono andati in Say. Serve per zoneChannelID, channelBaseName e chiavi canale |
| Payload `CHAT_MSG_YELL` | — | non verificato | — |
| Identità consegna (`lineID`) | `lineId` (parziale) | unicità verificata | Valori 6, 7, 8, 9, 36 tutti distinti, anche per due testi identici (7 e 8). **Da verificare:** stesso `lineID` per tutte le callback quando più finestre chat mostrano il canale (catturata una sola finestra, `ChatFrame1`) |
| Consegna a frame addon | `eventFrame` | **verificato** | Un `OnEvent` per messaggio (`frameEvents = 1` per ogni linea) |
| Valori secret nella chat | — | assenti fuori istanza | Nessun argomento secret in 5 campioni. Istanze/encounter non provati |
| API canali | — | presenti, forma non verificata | `GetChannelList`, `GetChannelName`, `C_ChatInfo.GetChannelInfoFromIdentifier`, `C_ChatInfo.GetChannelShortcut` sono funzioni. L'adapter le usa con controlli di tipo e ripiega sui canali visti nei messaggi |
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

## Comportamento attuale

- Filtro: non registrato finché `payload` non è verificato anche per i canali.
  `/fcg filter` viene rifiutato con spiegazione.
- Osservazione via frame eventi sui soli canali selezionati.
- Valori secret: messaggio ignorato, contatore `unreadable`, nessun errore.

## Prove mancanti per aprire il gate

1. Messaggi `fcgprobe-pass …` e `fcgprobe-hide …` inviati **nel canale**
   `fcgprobetest` (scrivendo `/<numero del canale> testo`, non in Say).
2. Lo stesso con **due finestre chat** che mostrano quel canale.
3. `/reload` e `/fcgprobe` (`loads 2`).
4. Facoltativo: un messaggio in un'istanza per i valori secret.

## Limiti noti

- Beta mobile: ripetere il probe a ogni build importante.
- Dove gli argomenti sono secret la chat resta invariata.
- Nessuna compatibilità dichiarata con altri addon chat finché non provata.
