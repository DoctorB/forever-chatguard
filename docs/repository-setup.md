# Impostazioni repository: confronto con HC One Button

Modello: `DoctorB/hc-one-button` (identificato dal remoto del checkout locale
`C:\Work\hc-one-button` e dall'addon installato, `## Author: DoctorB`).
Destinazione: `DoctorB/forever-chatguard`. Nessun valore sensibile in questo file.

Stato: **incompleto**. Le impostazioni remote non sono ancora state lette:
in questo ambiente manca una CLI GitHub autenticata (`gh` non installato) e
l'uso del token di Git Credential Manager per chiamate API è stato bloccato
dal controllo dei permessi della sessione. La colonna "osservato" contiene solo
quanto ricavabile dai file del modello; il resto va letto via API.

| Impostazione | Osservato nel modello | Desiderato per Forever ChatGuard | Rilevato dopo la modifica | Differenza / motivo |
| --- | --- | --- | --- | --- |
| Visibilità | da leggere | invariata (non si cambia per imitare il modello) | da leggere | — |
| Branch predefinito | `main` (checkout locale) | `main` | `main` (`git ls-remote`) | — |
| Collaboratori/team | da leggere; il workflow cita `DoctorB` e `DrCalibano` | solo gli accessi effettivamente decisi per il nuovo progetto | da leggere | `DrCalibano` non viene invitato né autorizzato solo perché compare nel workflow del modello |
| GitHub Actions abilitate | sì (workflow presente e usato) | sì | da leggere | — |
| Action consentite | da leggere | action pinnate a SHA (`actions/checkout` v7.0.1, `actions/upload-artifact` v7.0.1, stessi SHA del modello) | — | — |
| Permessi predefiniti `GITHUB_TOKEN` | da leggere; workflow con `contents: read` | read; `contents: write` solo nel job di release | da leggere | La release GitHub con ZIP richiede `contents: write` nel solo job `release` |
| Creazione/approvazione PR da Actions | da leggere | disattivata (non usata) | da leggere | — |
| Protezione branch / ruleset | da leggere | come il modello; check obbligatorio rinominato `checks` (job CI) | da leggere | — |
| Regole su tag e release | da leggere | come il modello | da leggere | — |
| Environment di rilascio | nessuno (secret di repository, da `docs/RELEASING.md` del modello) | nessuno, come il modello | — | — |
| Secret CurseForge | `CF_API_TOKEN` (repository secret) | `CF_API_TOKEN` (repository secret) | da creare | Valore non recuperabile dal modello: va impostato dall'utente |
| Variabile progetto | ID fisso nello script del modello | `CF_PROJECT_ID` (repository variable) | da creare | Mai copiare l'ID di HC One Button |
| Allowlist attori del workflow | `DoctorB`, `DrCalibano` | `DoctorB` | — | Ridotta finché non è deciso l'accesso di altri |
| Webhook / GitHub App / deploy key / runner | da leggere | solo se necessari: nessuno previsto | da leggere | Upload via Actions, nessun webhook CurseForge |

## Da fare per completare il confronto

1. Rendere disponibile una CLI autenticata, ad esempio:
   `winget install GitHub.cli` e poi `! gh auth login` nella sessione.
2. Leggere modello e destinazione:
   `gh api repos/DoctorB/hc-one-button`, `.../collaborators`, `.../actions/permissions`,
   `.../actions/permissions/workflow`, `.../branches/main/protection`, `.../rulesets`,
   `.../environments`, `.../actions/secrets` (solo nomi), `.../actions/variables`, `.../hooks`.
3. Applicare le differenze pertinenti a `DoctorB/forever-chatguard`, rileggere e
   compilare la colonna "rilevato".
