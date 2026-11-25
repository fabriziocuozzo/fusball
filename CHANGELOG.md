# Changelog

## v3.0 - 25/11/2026
Ruoli portiere (P) e attaccante (A), scambiabili anche durante la partita. Il tabellone è diviso in due metà per quadrato: un tocco assegna il gol al marcatore, sempre. Pulsante AG per gli autogol (il gol va agli avversari, attribuito a chi lo ha fatto). Nuova scheda Statistiche > Marcatori; gol e autogol nella scheda giocatore e nel podio del mese; frasi dedicate agli autogol.

Per aggiornare: eseguire `sql/04_marcatori.sql` su Supabase PRIMA di pubblicare l'app.

## v2.0 - 25/11/2026
Accesso con nome e PIN personali. Tre gruppi di permessi: amministratore, normale e solo lettura. Nuova scheda Impostazioni > Utenti per l'amministratore. Ogni partita ricorda chi l'ha inserita. Il gruppo normale può correggere o annullare la propria ultima partita entro 3 minuti dal salvataggio. Corretto: in modalità ospite sparivano le righe delle squadre vincitrici nello Storico.

Per aggiornare: eseguire `sql/03_utenti_gruppi.sql` su Supabase prima di pubblicare l'app.

## v1.0 - 24/11/2026
Prima versione: accesso con PIN e ospite in sola lettura, tabellone a schermo intero, giocatori, storico, statistiche (persone, coppie, record, ELO, badge), sfida del giorno, squadre casuali, podio del mese, condividi risultato (PNG), export CSV / PDF / backup JSON, coda offline, PWA.
