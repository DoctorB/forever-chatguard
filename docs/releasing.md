# Rilascio: GitHub → CurseForge

Un solo meccanismo di upload: il workflow `.github/workflows/release.yml`.
Non attivare il webhook di packaging di CurseForge e non aggiungere
`.pkgmeta`: due meccanismi sullo stesso tag potrebbero caricare file diversi.
La scelta di uno script Python stdlib (come in HC One Button) al posto di
BigWigsMods/packager evita dipendenze esterne e rende il pacchetto verificabile
byte per byte (SHA-256 nel `manifest.json`).

## Prerequisiti (una tantum)

1. **Gate di compatibilità superato** in `docs/compatibility.md`: tutti i flag
   `true` e `<!-- release-gate: open -->`, con evidenze. Senza, il workflow si
   ferma prima di creare la release GitHub e prima di contattare CurseForge.
2. **Progetto CurseForge** `1744553`, con categoria e versione di
   gioco realmente corrispondenti a WoW Forever. Il tipo di versione CurseForge
   di Forever è fissato nello script (`FOREVER_VERSION_TYPE = 88568`: unico tipo
   che contiene `1.60.1`, id 17053; confermato dall'utente nel form di upload il
   2026-10-14). Lo script rifiuta di caricare se quel tipo non contiene **una sola**
   versione uguale a quella derivata dal TOC (`16001` → `1.60.1`).
   Non si ripiega mai su Classic Era, Hardcore o Retail.
3. Repository `DoctorB/forever-chatguard`, **Settings → Secrets and variables → Actions**:
   - secret `CF_API_TOKEN`: token di upload CurseForge dell'autore;
   - variable `CF_PROJECT_ID`: ID numerico del progetto creato (non quello di HC One Button).
   Non incollare il token in chat, issue, file o log.

## Pubblicare una versione

1. Completare `docs/manual-tests.md` sulla build target.
2. Aggiornare insieme `## Version` nel TOC, `ns.VERSION` in `Bootstrap.lua` e
   la sezione `## <versione>` in `CHANGELOG.md` (testo pubblico delle note).
3. Commit, push, CI verde sul commit.
4. Tag annotato sul commit verificato e push del tag:
   `git tag -a v0.1.0 -m "Forever ChatGuard 0.1.0"` → `git push origin v0.1.0`.
   Pre-release con suffisso: `v0.2.0-beta.1` (GitHub pre-release, CurseForge beta).
5. Il workflow (solo per l'attore `DoctorB`):
   ripete tutti i controlli sul commit del tag → verifica tag = TOC = runtime =
   changelog → costruisce e verifica lo ZIP → controlla il gate → rifiuta upload
   doppi → crea la release GitHub con lo stesso ZIP → registra
   `curseforge-attempt.json` → carica su CurseForge → allega
   `curseforge-receipt.json`.

## Verifica remota

- Run del workflow verde e ZIP/manifest negli artifact.
- Release GitHub con ZIP e ricevuta; lo SHA-256 dello ZIP è nel `manifest.json`.
- Su CurseForge distinguere: **caricato** (ricevuta con file ID),
  **in revisione** (stato moderazione), **pubblicato e scaricabile**.
  Una ricevuta non significa disponibilità pubblica.

## Recupero da errore

- **Fallimento prima di "Record the upload attempt"**: correggere la causa
  esterna e lanciare *Run workflow* con lo stesso `tag`. Nessun rischio di
  doppio upload.
- **Fallimento durante/dopo l'upload senza ricevuta** (timeout, risposta
  ambigua): un timeout non prova che l'upload sia fallito. Aprire la pagina
  Files del progetto CurseForge.
  - Se il file c'è: non rilanciare. Annotare il file ID nella release GitHub.
  - Se non c'è: *Run workflow* con lo stesso `tag` e
    `confirm_curseforge_checked = true`.
- **Ricevuta presente**: quella versione è caricata; il workflow rifiuta ogni
  nuovo upload.
- **Contenuto sbagliato già pubblicato**: mai spostare o riusare un tag
  pubblicato. Rilascio correttivo con nuova versione (es. `v0.1.1`).
- Se la release GitHub esiste già con uno ZIP diverso, il workflow si ferma:
  nessuna sostituzione silenziosa.

## Cosa contiene lo ZIP

Solo la cartella `ForeverChatGuard/` con TOC, i file elencati nel TOC,
`README.md`, `CHANGELOG.md` e `LICENSE`. Esclusi: `.git`, `.github`, test,
documenti interni, script, probe, specifiche agentiche, segreti e log.
Timestamp e ordine deterministici: input identici producono lo stesso SHA-256.
