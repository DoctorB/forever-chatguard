# Impostazioni repository: confronto con HC One Button

Modello: `DoctorB/hc-one-button` (remoto del checkout locale
`C:\Work\hc-one-button`; addon installato con `## Author: DoctorB`), letto
in sola lettura. Destinazione: `DoctorB/forever-chatguard`.
Lettura via API REST con `gh` autenticato come `DoctorB` il 2026-10-14.
Nessun valore sensibile in questo file: dei secret si leggono solo i nomi.

| Impostazione | Osservato nel modello | Desiderato per Forever ChatGuard | Rilevato (2026-10-14) | Differenza / motivo |
| --- | --- | --- | --- | --- |
| Visibilità | public | invariata | public | — (non si cambia per imitare il modello) |
| Branch predefinito | `main` | `main` | `main` | — |
| Collaboratori | `DoctorB` admin, `DrCalibano` write | da decidere dal proprietario | `DoctorB` admin | **Aperta:** invitare `DrCalibano` è una decisione dell'utente; non viene fatta per imitazione |
| Team | nessuno | nessuno | nessuno | — |
| Inviti pendenti | nessuno | nessuno | nessuno | — |
| GitHub Actions | abilitate, tutte le action consentite, SHA pinning non obbligatorio | uguale | uguale | — (i workflow fissano comunque le action a SHA) |
| Permessi predefiniti `GITHUB_TOKEN` | `read` | `read` | `read` | — ; solo il job `release` chiede `contents: write` |
| Approvazione PR da Actions | disattivata | disattivata | disattivata | — |
| Accesso workflow da altri repo | n/a (repo pubblico) | n/a | n/a | — |
| Protezione branch `main` | nessuna | come il modello | nessuna | — |
| Ruleset (branch/tag) | nessuno | come il modello | nessuno | — |
| Environment | nessuno | nessuno | nessuno | — |
| Secret Actions | `CF_API_TOKEN` | `CF_API_TOKEN` | **assente** | Valore non leggibile dal modello: va impostato dall'utente con il token CurseForge |
| Variabili Actions | nessuna (ID nello script) | `CF_PROJECT_ID` | **assente** | Richiede il progetto CurseForge di Forever ChatGuard; mai l'ID di HC One Button |
| Webhook | nessuno | nessuno | nessuno | Nessun webhook di packaging CurseForge |
| Deploy key | nessuna | nessuna | nessuna | — |
| Runner self-hosted | nessuno | nessuno | nessuno | — |
| Secret scanning / push protection | attivi | attivi | attivi | — |
| Dependabot security updates | disattivati | come il modello | disattivati | — |
| Merge (merge/squash/rebase), auto-merge, delete branch | tutti consentiti; auto-merge e delete branch disattivati | uguale | uguale | — |
| Installazioni GitHub App | non elencabili con un token OAuth | — | non elencabili | Vincolo API: va controllato in Settings → Integrations |
| Allowlist attori nel workflow di rilascio | `DoctorB`, `DrCalibano` | `DoctorB` | `DoctorB` | Allineabile se `DrCalibano` riceve accesso |

## Verifica dei permessi effettivi

- Push su `main` con l'identità dell'utente: riuscito (`6ae82ef..2120917`).
- CI con `GITHUB_TOKEN` in sola lettura: verde (run 38540825261).
- Rilascio: non provato; resta bloccato dal gate di compatibilità e dal secret mancante.
  Nessuna operazione distruttiva usata come prova.

## Interventi rimasti all'utente

1. Decidere se invitare `DrCalibano` (write, come nel modello). In quel caso
   va aggiunto anche all'allowlist di `.github/workflows/release.yml`.
2. Creare il secret `CF_API_TOKEN` (Settings → Secrets and variables → Actions),
   ad esempio con `gh secret set CF_API_TOKEN --repo DoctorB/forever-chatguard`
   in un terminale proprio: il valore viene chiesto senza eco, mai in chat.
3. Dopo la creazione del progetto CurseForge:
   `gh variable set CF_PROJECT_ID --repo DoctorB/forever-chatguard --body <id>`.
