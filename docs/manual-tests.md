# Checklist manuale sul client WoW Forever

Da eseguire per ogni build candidata alla release (spec §14). Registrare
build (`/dump GetBuildInfo()`), data, esecutore ed esito per ogni voce.
Usare solo un canale privato (`/join fcgtest`) o un collaboratore consenziente:
mai generare spam nei canali pubblici.

Stato attuale: **non eseguita**. Nessuna voce è verificata in gioco.

| # | Verifica | Esito atteso | Build | Data | Esito |
| --- | --- | --- | --- | --- | --- |
| 1 | Installazione pulita, caricamento | Nessun errore Lua; `/fcg status` risponde | | | non eseguita |
| 2 | Primo avvio | Modalità osservazione, nessun canale; `/fcg channel list` propone i canali visti | | | non eseguita |
| 3 | Messaggi sintetici nel canale privato | Contatori `evaluated/allowed` coerenti | | | non eseguita |
| 4 | Duplicati, raffiche, termini letterali | Motivazioni come da fixture (`tests/test_engine.lua`) | | | non eseguita |
| 5 | Due o più finestre chat sullo stesso canale | Stessa decisione ovunque; contatori incrementati una volta | | | non eseguita |
| 6 | Cambio zona, abbandono/rientro, numerazione diversa | Selezione canale conservata (chiave stabile) | | | non eseguita |
| 7 | Off/on, observe/filter, modifica regole in tempo reale | Effetto immediato; nessuna decisione obsoleta | | | non eseguita |
| 8 | `/reload` e logout | Impostazioni conservate; quarantena e cronologie azzerate; nessun testo chat nel file SavedVariables | | | non eseguita |
| 9 | Messaggi lunghi, accenti, item link, markup inatteso | Nessun crash; testo mostrato in modo sicuro | | | non eseguita |
| 10 | Pannello aperto in combattimento | Nessun `ADDON_ACTION_BLOCKED` | | | non eseguita |
| 11 | Convivenza con un altro addon chat (nome e versione) | Entrambi funzionanti | | | non eseguita |
| 12 | API opzionale assente | Degrado spiegato una volta; chat visibile | | | non eseguita |

Limiti aperti da riportare insieme ai risultati: contesti con argomenti
secret, comportamento in istanze/encounter, eventuali differenze tra build.
