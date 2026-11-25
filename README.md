# Fusball

Calcio balilla 2 contro 2: tabellone, storico, statistiche, ELO, badge. PWA statica su GitHub Pages + Supabase (schema `fusball`). Nessuna dipendenza.

## Setup

1. **Supabase** (stesso progetto delle altre app): SQL Editor → incolla `sql/schema.sql`.
   **Prima di eseguirlo** sostituisci `CAMBIA_IL_PIN` con un PIN di 4-6 cifre. Non salvare il PIN reale nel repository.
   Poi esegui `sql/03_utenti_gruppi.sql`: il PIN diventa quello dell'utente admin "Fabrizio Cuozzo" (da v2.0 si entra con nome e PIN). Se l'app era gia' in uso (v1.0), basta eseguire solo il 03, e poi `notify pgrst, 'reload schema';`.
2. Supabase → Settings → API → **Exposed schemas**: aggiungi `fusball` e salva.
3. `config.js`: contiene già URL e chiave pubblica `anon` del progetto. Mai la `service_role`.
4. **Repository GitHub** `fusball` (pubblico) con questi file; Settings → Pages → branch `main`, cartella root.
5. **Dominio**: record CNAME su Aruba `fusball` → `fabriziocuozzo.github.io`, poi dominio personalizzato `fusball.fccowork.it` in Pages e HTTPS attivo.
6. **Keepalive**: repo → Settings → Secrets → Actions: `SUPABASE_URL` e `SUPABASE_ANON_KEY`. Il workflow `.github/workflows/keepalive.yml` pinga Supabase ogni giorno.
   Attenzione: GitHub disattiva i workflow programmati dei repo pubblici dopo 60 giorni senza commit. Basta un commit, oppure riattivarlo dalla scheda Actions.

## Utenti e gruppi (v2.0)

- Si entra con **nome e PIN**. "Entra come ospite" resta senza PIN, in sola lettura.
- Gruppi: **Amministratore** (tutto, compresa la gestione utenti), **Normale** (avvia e chiude partite, mescola le squadre, crea giocatori dal tabellone; corregge o annulla la *propria* ultima partita entro 3 minuti), **Solo lettura**.
- L'amministratore gestisce gli utenti da Impostazioni > Utenti. Ogni utente cambia il proprio PIN da Impostazioni > Sicurezza.
- I permessi di ogni gruppo sono nella tabella `fusball.gruppi` (colonna `permessi`) e il database li controlla a ogni scrittura; l'interfaccia mostra solo cio' che e' consentito. La finestra di correzione e' `recente_min` del gruppo normale.
- PIN dimenticato da un utente: l'admin lo reimposta. PIN dimenticato dall'admin: da SQL Editor, `update fusball.utenti set pin_hash = extensions.crypt('NUOVO', extensions.gen_salt('bf')) where lower(nome) = 'fabrizio cuozzo';`

## Marcatori, ruoli e autogol (v3.0)

- In Nuova partita la riga 1 di ogni squadra e' il portiere (P), la riga 2 l'attaccante (A). Il pulsante Scambia (e il ⇄ sul tabellone) li scambia anche in partita.
- Sul tabellone ogni quadrato e' diviso in due meta', una per giocatore: un tocco = gol di quel giocatore. AG = autogol (punto agli avversari, attribuito a chi lo ha fatto).
- Il gol e' del giocatore a prescindere dal ruolo; il ruolo serve per le statistiche (Statistiche > Marcatori).
- Database: `sql/04_marcatori.sql` aggiunge `partite.marcatori` e `partite_giocatori.pos`. Va eseguito prima di pubblicare l'app v3.0.

## Uso

- PIN → scrive. "Entra come ospite" → sola lettura, stesso link.
- Offline: l'app mostra l'ultimo snapshot e mette le scritture in coda; si sincronizza da sola al ritorno online.
- **Backup**: Impostazioni > Esporta > Backup JSON. Fallo ogni tanto: il repository pubblico non può ospitare dati.

## Versioning

Versione X.0 (v1.0, v2.0...). A ogni modifica aggiornare: commento iniziale di `index.html`, `<title>`, `APP_VERSION`/`APP_DATE` in `index.html`, `APP_VERSION` in `sw.js` (nome cache), `CHANGELOG.md` e scheda Changelog.
