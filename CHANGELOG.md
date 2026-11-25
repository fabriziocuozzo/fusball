# Changelog

## v2.0 - 25/11/2026
Accesso con nome e PIN personali. Tre gruppi di permessi: amministratore, normale e solo lettura. Nuova scheda Impostazioni > Utenti per l'amministratore. Ogni partita ricorda chi l'ha inserita. Il gruppo normale può correggere o annullare la propria ultima partita entro 3 minuti dal salvataggio. Corretto: in modalità ospite sparivano le righe delle squadre vincitrici nello Storico.

Per aggiornare: eseguire `sql/03_utenti_gruppi.sql` su Supabase prima di pubblicare l'app.

## v1.0 - 24/11/2026
Prima versione: accesso con PIN e ospite in sola lettura, tabellone a schermo intero, giocatori, storico, statistiche (persone, coppie, record, ELO, badge), sfida del giorno, squadre casuali, podio del mese, condividi risultato (PNG), export CSV / PDF / backup JSON, coda offline, PWA.
