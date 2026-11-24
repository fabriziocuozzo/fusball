# Fusball

Calcio balilla 2 contro 2: tabellone, storico, statistiche, ELO, badge. PWA statica su GitHub Pages + Supabase (schema `fusball`). Nessuna dipendenza.

## Setup

1. **Supabase** (stesso progetto delle altre app): SQL Editor → incolla `sql/schema.sql`.
   **Prima di eseguirlo** sostituisci `CAMBIA_IL_PIN` con un PIN di 4-6 cifre (poi cambialo dall'app: Impostazioni > Sicurezza). Non salvare il PIN reale nel repository.
2. Supabase → Settings → API → **Exposed schemas**: aggiungi `fusball` e salva.
3. `config.js`: contiene già URL e chiave pubblica `anon` del progetto. Mai la `service_role`.
4. **Repository GitHub** `fusball` (pubblico) con questi file; Settings → Pages → branch `main`, cartella root.
5. **Dominio**: record CNAME su Aruba `fusball` → `fabriziocuozzo.github.io`, poi dominio personalizzato `fusball.fccowork.it` in Pages e HTTPS attivo.
6. **Keepalive**: repo → Settings → Secrets → Actions: `SUPABASE_URL` e `SUPABASE_ANON_KEY`. Il workflow `.github/workflows/keepalive.yml` pinga Supabase ogni giorno.
   Attenzione: GitHub disattiva i workflow programmati dei repo pubblici dopo 60 giorni senza commit. Basta un commit, oppure riattivarlo dalla scheda Actions.

## Uso

- PIN → scrive. "Entra come ospite" → sola lettura, stesso link.
- Offline: l'app mostra l'ultimo snapshot e mette le scritture in coda; si sincronizza da sola al ritorno online.
- **Backup**: Impostazioni > Esporta > Backup JSON. Fallo ogni tanto: il repository pubblico non può ospitare dati.

## Versioning

Versione X.0 (v1.0, v2.0...). A ogni modifica aggiornare: commento iniziale di `index.html`, `<title>`, `APP_VERSION`/`APP_DATE` in `index.html`, `APP_VERSION` in `sw.js` (nome cache), `CHANGELOG.md` e scheda Changelog.
