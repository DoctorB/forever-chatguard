# Forever ChatGuard — Specifica di implementazione per Claude Code

Versione documento: 1.2 — 14 ottobre 2026  
Stato: specifica operativa per sviluppo, repository e pubblicazione automatizzata; compatibilità client da verificare.

## 1. Mandato e perimetro

Claude Code deve realizzare Forever ChatGuard e gestire autonomamente l'intero ciclo: inizializzazione del repository esistente, configurazione dei permessi, implementazione, test, commit, push, configurazione delle pipeline, versionamento e pubblicazione su CurseForge. Questa specifica autorizza tali operazioni nell'account e nel progetto dell'utente, senza richiedere conferme ripetute per ogni commit, push, tag o release conforme ai requisiti.

Repository di destinazione: **https://github.com/DoctorB/forever-chatguard**. L'utente lo ha già creato; non creare un altro repository. Verificarne lo stato effettivo prima di inizializzarlo. Per permessi e impostazioni di accesso, HC One Button è il modello da ispezionare e applicare al nuovo progetto, adattando i valori specifici.

Usare credenziali e identità già configurate. Richiedere all'utente soltanto dati o accessi indispensabili non ricavabili dall'ambiente, completando prima tutte le attività indipendenti. Non considerare la sola preparazione di un workflow come conclusione della pubblicazione.

Destinazione esclusiva: il client/server che l'utente identifica come **WoW Forever**. Non assumere che sia equivalente a Retail, Classic Era o Hardcore. Non implementare supporto per questi altri prodotti. Non assumere una build, un numero Interface, una versione Lua o disponibilità di API sulla base del solo nome Forever.

Le funzionalità e i valori predefiniti descritti sotto sono decisioni progettuali. Non costituiscono risultati verificati di una ricerca sulla community.

## 2. Obiettivo del prodotto

Ridurre il rumore nella chat pubblica attraverso regole locali, trasparenti e reversibili: duplicati ravvicinati, raffiche dello stesso autore e contenuti che il giocatore sceglie esplicitamente di filtrare. Preservare conversazioni, annunci di gruppo e compravendite legittime.

Il giocatore deve poter capire perché un messaggio è stato nascosto, rivederlo in una quarantena locale e disabilitare immediatamente il filtro.

### Inclusioni MVP

- Attivazione/disattivazione globale e per canale pubblico supportato.
- Modalità osservazione iniziale: analizza e mostra cosa avrebbe nascosto, senza nascondere.
- Duplicati dello stesso autore nello stesso canale.
- Limitazione facoltativa delle raffiche dello stesso autore.
- Parole o frasi letterali definite dal giocatore.
- Elenco locale di autori consentiti e bloccati.
- Quarantena temporanea, motivazione delle decisioni, contatori e diagnostica.
- Impostazioni persistenti con validazione e migrazioni.
- Interfaccia italiana e inglese; fallback inglese per stringhe mancanti.

### Esclusioni MVP

- Nessun invio automatico di messaggi, segnalazioni, inviti o modifiche alla lista ignore del gioco.
- Nessun punteggio pubblico degli utenti, blacklist condivisa o sincronizzazione tra giocatori.
- Nessun servizio esterno, telemetria, AI remota o download di regole nel runtime dell'addon. GitHub e CurseForge sono invece previsti per sviluppo e distribuzione.
- Nessuna classificazione automatica delle persone come bot, venditori o truffatori.
- Nessun filtro predefinito dei sussurri, della chat di gruppo, raid, gilda, sistema o combattimento.
- Nessun aggiramento delle restrizioni del client e nessun hook invasivo quando manca un punto di integrazione supportato.

## 3. Gate obbligatorio: verificare il client

Prima dell'adapter di produzione, raccogliere e documentare:

| Informazione | Evidenza richiesta |
| --- | --- |
| Identità del prodotto/client | Installazione o documentazione ufficiale del target Forever |
| Versione e build | Output diagnostico ottenuto dal client, con API disponibili |
| Numero Interface | Metadati del client o di un addon funzionante su quella build |
| Runtime Lua | Versione/caratteristiche effettivamente supportate |
| Eventi della chat | Nomi e payload osservati su messaggi sintetici |
| API dei filtri | Esistenza, firma, ritorni e semantica sulla build target |
| Identità messaggio | Eventuale ID stabile e suo ambito di unicità |
| Identità autore/canale | GUID, nome-reame e identificatore canale disponibili |
| UI e persistenza | API utilizzabili per pannelli, slash command e SavedVariables |

Scrivere `docs/compatibility.md` con build, data, metodo di verifica, risultati e limiti. Usare una tabella di capability, distinguendo verificato, assente e non verificato.

Nomi come `ChatFrame_AddMessageEventFilter` e `ChatFrame_RemoveMessageEventFilter` sono candidati da verificare, non garanzie di compatibilità. Non copiare le firme di un altro client come se fossero quelle di Forever.

Se il client non è disponibile, proseguire con motore puro, test, mock, UI astratta e documentazione. Segnalare l'integrazione in gioco come non verificata. Non inventare un numero Interface per confezionare una release dichiarata funzionante.

Se manca un filtro supportato, lasciare la chat invariata, disabilitare il filtraggio e mostrare una sola spiegazione locale. L'eventuale osservazione è ammessa soltanto se esiste un evento di lettura supportato.

## 4. Flusso utente

1. Al primo avvio, ChatGuard è in modalità osservazione.
2. Il pannello indica chiaramente modalità, canali selezionati e stato di compatibilità.
3. Il giocatore consulta gli esempi che sarebbero stati nascosti.
4. Può attivare il filtro, modificare le regole o consentire un autore.
5. In modalità filtro, i messaggi soppressi restano consultabili nella quarantena della sessione.
6. Disattivando ChatGuard, tutti i nuovi messaggi passano normalmente.

La quarantena non deve reinviare messaggi alla chat pubblica. «Mostra testo» apre una vista locale. «Consenti autore» cambia le decisioni future e invalida la cache appropriata.

## 5. Impostazioni iniziali

| Opzione | Default | Limiti |
| --- | --- | --- |
| enabled | true | Booleano |
| mode | observe | observe / filter |
| publicChannelSelection | nessun canale finché non identificato | Selezione esplicita o proposta confermata dal giocatore |
| duplicate.enabled | true | Solo stesso autore e canale |
| duplicate.windowSeconds | 30 | 5–120 |
| flood.enabled | false | Attivazione esplicita |
| flood.windowSeconds | 10 | 3–60 |
| flood.maxMessages | 5 | 3–30 |
| customTerms.enabled | false | Lista inizialmente vuota |
| quarantine.maxEntries | 200 | 20–500 |
| quarantine.ttlSeconds | 900 | 60–3600 |
| rules.maxCount | 100 | Limite rigido MVP |
| rule.maxBytes | 128 | Rifiutare input oltre limite |

Non riconoscere i canali solo dal numero visibile o da un nome inglese: numeri e localizzazioni possono cambiare. L'adapter risolve un'identità stabile quando disponibile e aggiorna le associazioni al cambio di zona/canale.

## 6. Contratti interni

Il motore non accede a globali WoW. Riceve configurazione, stato e un clock monotono iniettato.

```lua
message = {
  event = "adapter-verified-event",
  eventId = nil,       -- opzionale, con ambito documentato
  authorKey = "opaque-local-author-key",
  channelKey = "opaque-local-channel-key",
  text = "testo originale",
  now = 123.45,       -- clock monotono della sessione
  isSelf = false,
  eligible = true,
}

decision = {
  action = "allow",   -- allow oppure suppress
  reason = "PASS",    -- codice stabile
  ruleId = nil,
}
```

L'adapter trasforma `suppress` in sola osservazione quando `mode == "observe"`. I contatori distinguono messaggi unici valutati, consentiti, effettivamente nascosti e «avrebbe nascosto».

Codici minimi: `PASS`, `DISABLED`, `OUT_OF_SCOPE`, `SELF`, `ALLOWLIST`, `BLOCKLIST`, `CUSTOM_TERM`, `DUPLICATE`, `FLOOD`, `INVALID_INPUT`, `ENGINE_ERROR`.

Ordine vincolante:

1. Validazione input e stato di compatibilità: in caso di errore lascia passare.
2. Addon disabilitato o evento/canale fuori ambito: lascia passare.
3. Messaggio proprio: lascia passare.
4. Autore consentito: lascia passare.
5. Autore bloccato localmente: sopprimi nei soli canali selezionati.
6. Regola letterale abilitata e corrispondente: sopprimi.
7. Duplicato: sopprimi.
8. Raffica oltre limite, se abilitata: sopprimi.
9. Altrimenti lascia passare.

Allowlist prevale su blocklist; mostrare il conflitto nel pannello e proporne la correzione. Gli eventi fuori ambito non devono essere filtrati neppure per un autore bloccato.

## 7. Normalizzazione e regole

Conservare separatamente il testo originale per la vista locale. La copia di confronto può rimuovere markup di colore validato, normalizzare spazi e applicare lowercase ASCII. Per hyperlink, mantenere etichetta e identità del collegamento: due item diversi con lo stesso testo visibile non devono diventare automaticamente duplicati.

Non rimuovere cifre, prezzi, punteggiatura significativa o caratteri non ASCII. Non promettere case folding Unicode completo senza una libreria verificata. Non troncare sequenze UTF-8 a metà per la visualizzazione.

Per duplicati usare uguaglianza della copia normalizzata, non similarità fuzzy. Chiave logica: autore + canale + testo normalizzato, usando strutture annidate o un encoding non ambiguo. Se si usa un hash, verificare il testo per evitare collisioni.

Le regole utente sono sottostringhe letterali, case insensitive per ASCII; non Lua pattern, regex o codice. La UI deve spiegare che una parola breve può corrispondere anche all'interno di una parola più lunga. Rifiutare stringhe vuote o composte solo da spazi. Offrire anteprima locale prima dell'attivazione.

Nessuna regola predefinita contro termini come WTS, WTB, LFG, LFM, gold o boost: isolatamente possono comparire in messaggi legittimi. Nessun filtro basato su razza, nazionalità, lingua o altre caratteristiche personali.

## 8. Semantica temporale e callback multiple

### Duplicati

La prima occorrenza di una chiave passa e apre una finestra di 30 secondi. Le ripetizioni con `now < firstSeen + window` sono duplicate. Al confine esatto la finestra scade. Le ripetizioni soppresse non prolungano la finestra: dopo la scadenza una nuova occorrenza può passare.

### Raffiche

Per autore e canale conservare i timestamp degli eventi unici nell'intervallo `(now - window, now]`. I primi N passano, il messaggio N+1 è candidato alla soppressione. I duplicati contano come traffico ma non producono doppie voci o doppie motivazioni. Applicare la priorità delle regole già definita.

### Contabilità

Per un evento unico eleggibile non esentato da self/allowlist, aggiornare cronologia duplicati e raffiche una volta, anche se una regola a priorità superiore determina la decisione. Separare aggiornamento stato da selezione della motivazione.

I client possono richiamare un filtro per più finestre chat. La stessa consegna deve avere la stessa decisione in ogni finestra e incrementare i contatori una sola volta.

Preferire un identificatore evento verificato, qualificato da sessione e tipo evento. Non deduplicare callback e veri messaggi ripetuti usando solo testo/autore/timestamp arrotondato. Se manca un ID, validare nel client una strategia affidabile di acquisizione una volta e distribuzione delle decisioni. Se non è dimostrabile, disabilitare le regole stateful di duplicati/raffiche e dichiarare il limite; le regole stateless possono restare operative senza promettere contatori esatti per evento.

## 9. Architettura proposta

```text
ForeverChatGuard/
  ForeverChatGuard.toc
  Bootstrap.lua
  Locale/enUS.lua
  Locale/itIT.lua
  Core/Defaults.lua
  Core/Config.lua
  Core/Normalize.lua
  Core/Rules.lua
  Core/Engine.lua
  Core/Store.lua
  Adapters/Forever.lua
  UI/Commands.lua
  UI/Panel.lua
  UI/Quarantine.lua
  tests/runner.lua
  tests/fixtures.lua
  tests/test_engine.lua
  tests/test_config.lua
  tests/test_adapter.lua
  docs/compatibility.md
  docs/manual-tests.md
  docs/releasing.md
  .github/workflows/ci.yml
  .github/workflows/release.yml
  .pkgmeta
  .gitignore
  README.md
  CHANGELOG.md
  CLAUDE.md
```

Ordine di caricamento nel TOC: bootstrap/namespace, locale base e override, defaults/config, normalizzazione/store/regole/motore, adapter, UI. Nessuna dipendenza obbligatoria da altri addon. Namespace unico; evitare globali ulteriori salvo SavedVariables e slash command necessari.

Usare solo sintassi disponibile nel runtime accertato. Finché non verificato, preferire un sottoinsieme Lua conservativo, senza operatori o librerie moderne. Non presumere che `require`, filesystem o rete siano disponibili nel runtime in gioco.

## 10. Persistenza e limiti

SavedVariable proposta: `ForeverChatGuardDB`, soggetta a conferma sul client. Schema iniziale:

```lua
{
  schemaVersion = 1,
  enabled = true,
  mode = "observe",
  channels = {},
  duplicate = { enabled = true, windowSeconds = 30 },
  flood = { enabled = false, windowSeconds = 10, maxMessages = 5 },
  customTerms = {},
  allowlist = {},
  blocklist = {},
  ui = {},
}
```

Configurazione condivisa tra i personaggi della stessa installazione/account se il client lo consente; identità autori qualificate per reame o contesto equivalente. Nessuna conflazione tra nomi uguali su reami diversi.

Persistono solo impostazioni e liste esplicitamente modificate dall'utente. Testi chat, cronologie temporali, quarantena e cache decisioni rimangono in memoria e si azzerano al reload/logout.

Validare tipi, enum e limiti al caricamento. Migrazioni sequenziali e idempotenti su una copia; sostituire il DB soltanto a migrazione riuscita. Se lo schema è più nuovo di quello supportato, non sovrascriverlo: avviare in modalità disabilitata con messaggio locale. Gestire dati corrotti con default sicuri e avviso unico.

Limiti di memoria iniziali: 500 autori per canale, 20 canali, 5.000 chiavi duplicate totali, 2.000 decisioni in cache e quarantena di massimo 500 elementi. Applicare TTL e rimozione dei meno recenti. I limiti sono configurazioni interne, non promesse sulle prestazioni.

Input testuale oltre 4.096 byte: lasciare passare senza analisi e incrementare un contatore diagnostico, evitando che un troncamento provochi falsi positivi. Limitare anche la lunghezza memorizzata dei campi identità.

## 11. Interfaccia e comandi

Pannello semplice con stato, modalità, canali, regole, liste autori, quarantena e diagnostica. Ogni switch deve avere una breve spiegazione. Navigazione da tastiera e motivazioni testuali; non affidarsi soltanto ai colori.

Comandi proposti, da registrare se supportati:

| Comando | Risultato |
| --- | --- |
| `/fcg` o `/fcg help` | Aiuto breve |
| `/fcg status` | Stato, modalità e compatibilità |
| `/fcg on` | Abilita nella modalità corrente |
| `/fcg off` | Disabilita immediatamente |
| `/fcg observe` | Osservazione |
| `/fcg filter` | Filtraggio, solo con capability verificate |
| `/fcg config` | Apre impostazioni |
| `/fcg quarantine` | Apre messaggi trattenuti o osservati |
| `/fcg clear` | Svuota la quarantena |
| `/fcg reset` | Mostra conferma locale di ripristino |
| `/fcg reset confirm` | Ripristina dopo conferma |

Mostrare in quarantena ora locale della ricezione, canale, autore, testo e motivo; mantenere il clock monotono per il motore. Distinguere visivamente «nascosto» e «avrebbe nascosto».

Il testo proveniente dalla chat è dato non affidabile: renderizzarlo come testo sicuro, senza eseguire codice, comandi o hyperlink arbitrari. Non implementare importazioni Lua. Il reset richiede conferma perché cancella preferenze e liste.

## 12. Integrazione e resilienza

- Registrare e rimuovere solo i propri callback; nessun override globale di AddMessage.
- Mantenere invariati testo, ordine e argomenti dei messaggi consentiti.
- Verificare la preservazione degli argomenti nil intermedi e finali nel wrapper.
- Registrazione idempotente: toggling e reload non devono accumulare filtri.
- Contenere gli errori dell'addon; in caso di errore del motore lasciare passare il messaggio.
- Dopo tre errori del motore in 60 secondi, sospendere i filtri per la sessione e mostrare un avviso locale una sola volta; riattivazione manuale.
- Non sopprimere gli errori di altri addon né modificare il loro stato.
- Nessun lavoro continuo per frame: pulizia delle cache a piccoli lotti su eventi o timer supportati.
- Separare output diagnostico e chat filtrabile per evitare ricorsione.
- Cambi di regole invalidano la cache decisioni; cambi di finestre temporali svuotano le relative cronologie.
- Verificare convivenza con altri filtri senza dichiarare compatibilità universale.

## 13. Test automatici richiesti

Usare fixture sintetiche e clock simulato; nessun corpus di conversazioni private. Il test runner deve poter funzionare fuori dal gioco con dipendenze minime.

| Caso | Esito atteso |
| --- | --- |
| Addon disabilitato | Tutti i messaggi passano |
| Modalità observe | Nessuna soppressione reale; contatore wouldSuppress corretto |
| Canale non selezionato | Passa, nessun aggiornamento rate limit |
| Whisper/gruppo/gilda/sistema | Passa anche con autore in blocklist |
| Messaggio proprio | Passa |
| Autore in entrambe le liste | Passa per allowlist |
| Prima occorrenza / replica a +1 s | Passa / duplicato |
| Replica al limite esatto di 30 s | Passa e apre nuova finestra |
| Repliche intermedie soppresse | Non spostano la scadenza |
| Stesso testo, autore diverso | Non è duplicato |
| Stesso testo, canale diverso | Non è duplicato |
| Prezzo 10g e prezzo 100g | Non diventano uguali |
| Item diversi con stessa etichetta | Non diventano uguali |
| Sesta consegna unica in 10 s, limite 5 | FLOOD se nessuna regola prioritaria |
| Timestamp esattamente now-window | Escluso dalla finestra flood |
| Callback dello stesso evento in 3 finestre | Stessa decisione; un solo conteggio |
| Due eventi reali identici nello stesso istante | Due conteggi; secondo duplicato |
| Regola contenente `.`, `%`, `+` o `[` | Corrispondenza letterale |
| UTF-8, markup malformato, link | Nessun crash e testo sicuro |
| Input nil, tabella inattesa o sovralunghezza | Lascia passare senza errore |
| Errore indotto nel motore | Lascia passare; scatta circuit breaker previsto |
| Config corrotta o schema futuro | Recupero documentato, nessuna sovrascrittura distruttiva |
| Config modificata durante la sessione | Nessuna decisione obsoleta dalla cache |
| Cache piena e TTL scaduti | Limiti rispettati e memoria recuperata |
| ID messaggio assente | Degrado esplicito delle funzioni non garantibili |

Aggiungere test delle migrazioni e del contratto adapter con il payload effettivamente verificato. Non considerare i mock una prova di compatibilità in gioco.

## 14. Verifica manuale sul client Forever

Registrare build e risultati per ogni voce:

1. Installazione pulita, caricamento, nessun errore Lua.
2. Primo avvio in osservazione e selezione dei canali.
3. Messaggi sintetici con un collaboratore consenziente o ambiente di prova, senza generare spam nei canali pubblici.
4. Duplicati, raffiche e termini letterali secondo le fixture.
5. Due o più finestre chat sullo stesso canale.
6. Cambio zona, abbandono/rientro nel canale e numerazione diversa.
7. Off/on, observe/filter e modifica delle regole in tempo reale.
8. Reload e logout: impostazioni conservate, chat memorizzata eliminata.
9. Messaggi lunghi, accenti, item link e markup inatteso.
10. Apertura pannello in combattimento; nessuna operazione protetta non consentita.
11. Convivenza con almeno un altro addon chat disponibile sul target, riportandone versione.
12. API opzionale assente: degrado spiegato e chat visibile.

## 15. Prestazioni e criteri di accettazione

Eseguire un benchmark riproducibile di 10.000 eventi sintetici con più autori e canali; riportare runtime, macchina, tempo totale, distribuzione dei tempi se misurabile e picco di memoria. Obiettivo iniziale del solo motore: p95 inferiore a 1 ms per evento sulla macchina di riferimento. È un budget da misurare, non una garanzia universale.

Definition of Done MVP:

- Tutti i test automatici passano, con output e comando riproducibili.
- Nessun messaggio viene nascosto in observe, off o fuori ambito.
- Ragioni delle decisioni deterministiche e spiegabili.
- Callback multiple non moltiplicano lo stato; in alternativa degrado documentato e funzioni interessate disabilitate.
- Cache e quarantena rispettano limiti e TTL.
- Nessuna chat persiste su disco tramite ChatGuard.
- Build target, API e numero Interface verificati per una release installabile.
- Checklist manuale completata sul client Forever, con limiti aperti espliciti.
- ZIP installabile con una sola directory radice `ForeverChatGuard/`; nessuna directory annidata accidentalmente.
- README con installazione, comandi, limiti, disinstallazione e percorso delle impostazioni verificato sul target.
- Repository `DoctorB/forever-chatguard` configurato, permessi allineati al modello HC One Button e verificati, commit e tag pubblicati, CI verde sul commit della release.
- Pipeline di pubblicazione eseguita con successo e file CurseForge verificato; distinguere upload accettato, eventuale revisione e disponibilità pubblica.
- Nessuna attribuzione di autore o coautore a Claude Code nei commit, documenti, sorgenti o metadati distribuiti.

Se manca la prova sul client, consegnare un prototipo con etichetta **integrazione non verificata**; non dichiarare raggiunta la Definition of Done della release.

## 16. Piano di lavoro agentico

### Fase A — Ricognizione

Leggere workspace e istruzioni esistenti. Usare il repository `DoctorB/forever-chatguard` secondo la sezione 19, ispezionare HC One Button per configurare permessi e accessi, verificare il target e scrivere `docs/compatibility.md`. La consultazione del codice di HC One Button per spunti implementativi rimane facoltativa secondo la sezione 20. Individuare soltanto i blocchi che richiedono dati del client o accessi mancanti; proseguire autonomamente sulle parti indipendenti. Non cambiare altri addon o file del gioco.

### Fase B — Motore puro

Implementare defaults, normalizzazione, identità, regole, finestre temporali, cache e test. Usare clock iniettato e funzioni piccole. Concludere con test dei confini e delle callback multiple.

### Fase C — Persistenza e adapter

Implementare migrazioni, validazione e integrazione basata sulle capability verificate. Rendere esplicito ogni fallback. Provare carico/scarico idempotente e fail-open.

### Fase D — UI

Implementare comandi, impostazioni, quarantena e localizzazione. Collegare le modifiche alla configurazione attraverso un unico percorso di validazione e invalidazione cache.

### Fase E — Validazione e confezionamento

Eseguire test, benchmark e checklist manuale dove possibile. Preparare README, changelog e pacchetto. Nel rapporto finale distinguere completato, verificato automaticamente, verificato in gioco e bloccato da assenza del client.

### Fase F — Pubblicazione e verifica remota

Gestire commit e push durante il lavoro, configurare CI/CD e progetto CurseForge, correggere gli errori della pipeline, creare il tag di versione e pubblicare appena i criteri sono soddisfatti. Verificare il risultato remoto e fornire collegamenti a repository, esecuzione CI, release e file CurseForge. Un upload in revisione va riportato come tale, senza dichiararlo già disponibile pubblicamente.

Per ogni fase produrre un riepilogo breve dei file modificati, verifica eseguita e problemi residui. Non avviare sviluppo di funzionalità escluse. La pubblicazione su CurseForge e la gestione del repository sono già comprese nel mandato; non richiedono una richiesta separata.

## 17. Prompt iniziale da fornire a Claude Code

```text
Implementa Forever ChatGuard seguendo FOREVER_CHATGUARD_CLAUDE_CODE_SPEC.md.

Il target è esclusivamente WoW Forever. Leggi prima le istruzioni del repository.
Non assumere che le API di Retail, Classic Era o Hardcore valgano per Forever.
Verifica build, runtime Lua, TOC, eventi, filtri e payload; documenta le prove
in docs/compatibility.md. Se il client non è disponibile, completa motore,
mock, test e documentazione e segnala l'integrazione come non verificata.

Procedi per le fasi A–F. Usa il repository già creato dall'utente:
https://github.com/DoctorB/forever-chatguard
Non creare un altro repository. Configura tutti i permessi e le impostazioni
di accesso sul modello del repository HC One Button, ispezionandone lo stato
reale e adattando i valori al nuovo progetto. Verifica le impostazioni applicate.
Gestisci autonomamente commit, push, CI/CD, tag e pubblicazione su CurseForge
secondo la sezione 19.
Non fermarti alla preparazione dei file della pipeline: eseguila e verifica
il risultato remoto. Chiedi solo gli accessi o i dati indispensabili mancanti.
Puoi consultare HC One Button per spunti, rispettandone licenza e perimetro.
Non figurare mai come autore o coautore nei commit, nei documenti, nei sorgenti,
nel TOC, nei crediti o nelle release. Usa l'identità autorizzata dell'utente;
nessuna firma automatica o trailer di attribuzione a Claude Code.

Il primo avvio deve essere in osservazione.
Implementa regole deterministiche, quarantena temporanea, configurazione
validata, limiti di memoria e comportamento fail-open. Gestisci le callback
multiple per lo stesso messaggio senza duplicare contatori o rate limit.
Non introdurre rete, telemetria, messaggi automatici o blacklist condivise
nel runtime dell'addon; usa i servizi remoti necessari per CI e distribuzione.

Esegui test significativi e consegna codice, README, risultati delle verifiche
e limiti residui. Non inventare risultati di test in gioco. Non dichiarare
una release compatibile finché il gate del client non è stato superato.
```

## 18. Riferimenti tecnici e loro limiti

- Sorgente UI del client WoW, mirror Gethe: https://github.com/Gethe/wow-ui-source — materiale utile a individuare implementazioni da confrontare; selezionare revisione e famiglia corrette, senza assumere che corrispondano a Forever.
- Handler chat Mainline consultato come riferimento comparativo: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua — mostra elaborazione degli eventi chat di quel client; non dimostra compatibilità Forever.
- Implementazione storica dei filtri chat: https://github.com/tekkub/wow-ui-source/blob/live/FrameXML/ChatFrame.lua — riferimento storico per il concetto di callback; firme e semantica devono essere riverificate sul target.

I link a branch mobili non fissano una versione. Durante l'implementazione registrare commit o sorgente locale effettivamente usata.

## 19. Repository, commit, push e pipeline CurseForge

### Repository e identità

- Usare esclusivamente il repository esistente [DoctorB/forever-chatguard](https://github.com/DoctorB/forever-chatguard), già creato dall'utente. Clonarlo oppure collegare un checkout dedicato al remoto corretto; verificarne proprietà, branch e contenuto senza sovrascrivere lavoro estraneo. Non creare repository sostitutivi o duplicati.
- Owner e nome sono già definiti: `DoctorB/forever-chatguard`. Ispezionare la visibilità e le impostazioni attuali; allineare i permessi al modello HC One Button come descritto sotto. Non cambiare la visibilità del repository solo per imitare il modello: la visibilità non è un permesso operativo necessario alla pipeline.
- Configurare l'identità Git a livello del solo repository usando nome ed email autorizzati dell'utente, già presenti o verificabili nell'account. Non inventare dati personali e non modificare la configurazione globale.
- Non usare Claude, Claude Code, Anthropic, un modello o un assistente AI come autore, committer o coautore dei commit. Nessun trailer `Co-authored-by` riferito all'assistente, firma «Generated with» o credito equivalente nei messaggi di commit, documenti, sorgenti, TOC, changelog e note di rilascio.
- I riferimenti operativi allo strumento nelle istruzioni di sviluppo sono consentiti e non costituiscono attribuzione autoriale. Conservare gli avvisi e le attribuzioni legittime di eventuale codice di terzi.
- Verificare l'eventuale impostazione dello strumento che aggiunge attribuzioni automatiche e disabilitarla per il progetto prima del primo commit. Non supporre un nome di opzione: consultare la documentazione della versione installata.

### Permessi e impostazioni: modello HC One Button

Questa configurazione è parte obbligatoria del lavoro, non un suggerimento. Individuare il repository HC One Button dell'utente tramite repository accessibili, remoti locali o progetti esistenti. Non inventarne nome o URL e non sostituirlo con un progetto omonimo di terzi. Consultarlo in sola lettura e non modificarne impostazioni o accessi.

Ispezionare con API/CLI autenticata o interfaccia autorizzata sia il modello sia la destinazione. Il solo contenuto dei workflow non rivela tutti i permessi del repository. Preparare e poi applicare una matrice con impostazione, valore osservato nel modello, valore desiderato per Forever ChatGuard, valore rilevato dopo la modifica ed eventuale differenza motivata.

La matrice deve includere almeno:

- Accessi di collaboratori, team e ruoli effettivamente presenti, distinguendo autorizzazioni ereditate e specifiche del repository; adattare l'accesso al nuovo progetto e non invitare identità estranee solo perché compaiono in un workflow.
- Abilitazione di GitHub Actions, policy delle action consentite e accesso a workflow riutilizzabili.
- Permessi predefiniti di `GITHUB_TOKEN`, permessi espliciti dei singoli job ed eventuale facoltà di creare o approvare pull request, se usata dal modello.
- Branch predefinito, protezioni e ruleset, controlli obbligatori, revisioni richieste, regole di merge e restrizioni su push, tag e release. Adattare i nomi dei check a quelli della nuova CI.
- Environments di rilascio, branch/tag ammessi, regole di protezione e accessi ai secret. Rispettare eventuali revisioni obbligatorie; non rimuoverle per rendere la pipeline autonoma.
- Secret e variabili necessari per CurseForge e per eventuali altri passaggi già previsti; ispezionarne nomi, ambito e disponibilità, senza esporne i valori.
- Installazioni GitHub App, deploy key, webhook o runner solo se realmente usati e necessari; assegnare accesso al nuovo repository con gli strumenti consentiti.

Applicare autonomamente le impostazioni pertinenti che l'account consente di gestire. Il modello guida l'assetto, ma non autorizza a copiare project ID, chiavi private, credenziali o URL di destinazione dell'altro addon. Non ampliare privilegi oltre quelli necessari per riprodurre il flusso. Le policy di organizzazione o account che non sono modificabili a livello di repository vanno riportate come vincoli, senza cambiarle globalmente.

I valori dei secret GitHub esistenti non sono recuperabili dalla loro semplice enumerazione. Riutilizzare un secret condiviso solo se già disponibile tramite un ambito autorizzato e adatto al nuovo progetto; altrimenti configurare il secret necessario attraverso il canale sicuro disponibile o chiedere all'utente il solo intervento indispensabile.

Salvare il confronto privo di dati sensibili in `docs/repository-setup.md`. Dopo ogni modifica, rileggere lo stato remoto e verificare i permessi effettivi con CI, push e rilascio previsti, senza effettuare operazioni distruttive come prova. Segnalare le differenze imposte da piano GitHub, policy o funzionalità non disponibili; non dichiarare una parità non verificata.

Se non è possibile identificare HC One Button o leggere le sue impostazioni, chiedere il riferimento o l'accesso preciso mancante e proseguire con il lavoro indipendente. La configurazione dei permessi rimane incompleta finché il confronto non è verificabile.

### Flusso Git autonomo

1. Preparare `.gitignore`, struttura, README e istruzioni di progetto; escludere credenziali, cache, log locali e artefatti temporanei.
2. Creare commit piccoli e coerenti dopo verifiche pertinenti, con messaggi che descrivono il cambiamento e senza firme dell'assistente.
3. Eseguire push dei progressi completati; rispettare branch protection e flusso PR esistenti. Non usare force push, non riscrivere storia condivisa e non disabilitare controlli per far passare una release.
4. Ispezionare autore, committer, messaggio completo e file di ogni nuovo commit prima del push. Correggere attribuzioni automatiche nei commit locali non ancora pubblicati.
5. Attendere l'esito della CI, leggere i log, correggere i problemi e ripetere finché passa o emerge un impedimento esterno concreto.
6. Aggiornare versione e changelog, creare un tag annotato `vMAJOR.MINOR.PATCH` sul commit verificato e pubblicarlo. Prerelease con suffisso esplicito, per esempio `-beta.1`.

### Pipeline CI

Eseguire su push e pull request: controlli di sintassi sul runtime target, test del motore e dell'adapter, validazione TOC, controllo del pacchetto e verifica delle attribuzioni autoriali. Controllare i metadati dei commit e i campi di autore nei file; non usare una ricerca indiscriminata che vieti anche istruzioni legittime in `CLAUDE.md`.

Produrre un ZIP di prova senza upload per le PR. Verificare che contenga solo la cartella installabile `ForeverChatGuard/` e i file necessari. Escludere `.git`, `.github`, test, documenti interni, specifiche agentiche, segreti e log. Conservare licenze e avvisi richiesti. Usare permessi minimi e fissare le action esterne a revisioni immutabili verificate.

### Pipeline di rilascio

- Trigger su tag di versione; consentire un riavvio manuale controllato sulla stessa versione per recuperare un errore transitorio.
- Ripetere i controlli sul commit esatto del tag e verificare corrispondenza tra tag, versione dell'addon e changelog.
- Consentire pubblicazione solo se i requisiti di compatibilità e distribuzione sono documentati e soddisfatti. Non attribuire al client Forever una categoria o versione di gioco diversa per aggirare un controllo del portale.
- Preparare il pacchetto, validarne contenuto e metadati, quindi caricare esattamente quell'artefatto su CurseForge. Allegare lo stesso ZIP alla release GitHub se prevista dal workflow del progetto.
- Usare un solo meccanismo di upload: non attivare contemporaneamente webhook di packaging CurseForge e upload via Actions sullo stesso tag.
- Gestire un lock per versione e verificare la presenza di upload precedenti prima di riprovare: un timeout non prova che l'upload sia fallito. Non sostituire silenziosamente un file già pubblicato con contenuti differenti.
- Documentare in `docs/releasing.md` il recupero da errore, la verifica remota e il rilascio correttivo con nuova versione, senza spostare tag pubblicati.

Per il packaging valutare [BigWigsMods/packager](https://github.com/BigWigsMods/packager), che supporta ZIP e upload CurseForge, oppure un'integrazione diretta verificata con l'[Upload API di CurseForge](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-api). La scelta deve essere compatibile con Forever e produrre un pacchetto verificabile. Se si usa il packager, definire `.pkgmeta` e il project ID CurseForge secondo la documentazione della revisione scelta; non copiare identificativi da altri addon.

### Progetto CurseForge e accessi

Creare o configurare il progetto Forever ChatGuard nell'account dell'utente con gli strumenti e le sessioni autorizzate disponibili. Impostare nome, descrizione, categoria, licenza, versioni compatibili e changelog coerenti con il prodotto. Verificare che il target sia effettivamente distribuibile sul portale: l'autorizzazione a pubblicare non sostituisce i requisiti della piattaforma.

Ricavare il vero project ID dal progetto creato. Configurare il token di upload come secret del repository o dell'ambiente di rilascio. Il nome del secret interno può essere scelto dal progetto, ma deve essere mappato alla variabile richiesta dalla versione effettiva del tool. Non inserire token nei file, nei comandi stampati, nei log o nella documentazione; non chiedere di incollarli nella chat.

Se mancano login, token, un permesso o un passaggio del portale che richiede l'intervento dell'utente, completare repository, commit, push, CI e packaging per quanto consentito dagli accessi disponibili. Indicare precisamente l'unico intervento necessario e riprendere poi dal punto raggiunto. Non inventare credenziali, ID, approvazioni o risultati di pubblicazione.

### Esito richiesto

Consegnare URL del repository, versione/tag, commit rilasciato, URL dell'esecuzione CI/CD, nome e checksum del pacchetto, project ID e collegamento al file CurseForge. Distinguere «caricato», «in revisione» e «pubblicato e scaricabile». Segnalare gli eventuali blocchi esterni senza dichiarare completato il flusso prima della verifica remota.

## 20. HC One Button: modello dei permessi e riferimento implementativo

L'ispezione di **HC One Button** per permessi e impostazioni di accesso è obbligatoria secondo la sezione 19. Claude Code può inoltre consultarlo facoltativamente per spunti su struttura di un addon, convenzioni dell'utente, test, packaging, gestione delle versioni e pipeline CurseForge. Cercare prima nei repository e workspace già accessibili dell'utente; identificare il progetto corretto senza inventare un URL. Se non è disponibile, continuare autonomamente sulle parti indipendenti e riportare il blocco del confronto dei permessi.

Consultarlo in sola lettura. Non modificarlo e non riutilizzare i suoi project ID, token, nome, metadati o configurazioni di compatibilità. Prima di riusare codice verificarne la licenza e conservarne gli avvisi dovuti; se non è riutilizzabile, implementare autonomamente il comportamento necessario.

La consultazione di HC One Button non amplia il target: Forever ChatGuard rimane esclusivamente per WoW Forever e non acquisisce funzionalità Hardcore o Classic Era per analogia.
