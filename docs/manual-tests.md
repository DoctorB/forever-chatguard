# Checklist manuale sul client WoW Forever

Da eseguire per ogni build candidata alla release (spec §14). Registrare
build (`/dump GetBuildInfo()`), data, esecutore ed esito per ogni voce.
Usare solo un canale privato (`/join fcgtest`) o un collaboratore consenziente:
mai generare spam nei canali pubblici.

Stato attuale: **parziale** (build 1.60.1.70374, 2026-10-14, proprietario del
progetto, con probe e screenshot). Restano le voci segnate «da eseguire».

**Decisione del proprietario (2026-10-14):** la 1.0.0 viene pubblicata con
questa checklist parziale; le voci aperte saranno chiuse con le segnalazioni
degli utenti (issue GitHub) e con le versioni successive.

| # | Verifica | Esito atteso | Build | Data | Esito |
| --- | --- | --- | --- | --- | --- |
| 1 | Installazione pulita, caricamento | Nessun errore Lua; `/fcg status` risponde | 70374 | 2026-10-14 | ✅ nessun errore; `/fcg` risponde. Il blocco tastiera era del probe (corretto) |
| 2 | Primo avvio | Modalità osservazione, nessun canale | 70374 | 2026-10-14 | ✅ «observe», «Selected channels: none» (screenshot pannello) |
| 3 | Messaggi sintetici nel canale privato | Contatori coerenti | 70374 | 2026-10-14 | ✅ `fcgprobetest` analizzato, 2 voci «avrebbe nascosto» |
| 4 | Duplicati, raffiche, termini letterali | Motivazioni come da fixture | 70374 | 2026-10-14 | ⚠️ duplicati ✅ (`fcgprobe-pass due`, `ciao test`); raffiche e termini **da eseguire** |
| 5 | Più finestre chat sullo stesso canale | Stessa decisione ovunque; un conteggio | 70374 | 2026-10-14 | ✅ 10 callback per messaggio con lo stesso `lineID`, `frameEvents = 1`; righe identiche nelle due finestre visibili |
| 6 | Cambio zona, abbandono/rientro, numerazione | Selezione canale conservata | | | **da eseguire** |
| 7 | Off/on, observe/filter, regole in tempo reale | Effetto immediato; nascosto davvero in filtro | | | **da eseguire** (la modalità filtro di ChatGuard non è ancora stata provata in gioco) |
| 8 | `/reload` e logout | Impostazioni conservate; quarantena azzerata; nessun testo chat su disco | 70374 | 2026-10-14 | ⚠️ impostazioni conservate tra sessioni (`zone:1` selezionato) e file `ForeverChatGuard.lua` senza testo chat ✅; azzeramento quarantena dopo `/reload` **da osservare** |
| 9 | Messaggi lunghi, accenti, item link, markup | Nessun crash; testo sicuro | 70374 | 2026-10-14 | ⚠️ messaggi reali di General senza errori; item link e accenti **da eseguire** |
| 10 | Pannello aperto in combattimento | Nessun `ADDON_ACTION_BLOCKED` | | | **da eseguire** |
| 11 | Convivenza con un altro addon chat (nome e versione) | Entrambi funzionanti | | | **da eseguire** |
| 12 | API opzionale assente | Degrado spiegato; chat visibile | — | — | non applicabile su questo client (API presenti); coperto da `tests/test_adapter.lua` |
| 13 | Icona nella lista AddOns (riavvio completo del client) | Scudo di ChatGuard al posto del punto di domanda | 70450 | 2026-10-21 | ✅ scudo mostrato nella lista AddOns della selezione personaggio |

Limiti aperti da riportare insieme ai risultati: contesti con argomenti
secret, comportamento in istanze/encounter, eventuali differenze tra build.
