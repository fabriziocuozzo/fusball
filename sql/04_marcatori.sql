-- Fusball v3.0 - marcatori, ruoli e autogol
-- Da eseguire UNA volta nello SQL Editor di Supabase, PRIMA di pubblicare l'app v3.0 (dopo 03_utenti_gruppi.sql).
-- Cosa aggiunge:
--   * partite.marcatori: chi ha segnato ogni gol, in ordine, con il ruolo di quel momento e l'eventuale autogol.
--     Formato: elenco separato da virgole, un elemento per gol, nello stesso ordine di sequenza_gol.
--     Ogni elemento = posizione del giocatore (0-3) + ruolo (P/A) + tipo (n = gol, g = autogol). Esempio: 0Pn,3Ag,1An
--     Le posizioni 0 e 1 sono la squadra A, 2 e 3 la squadra B.
--   * partite_giocatori.pos: la posizione (0-3) del giocatore nella partita.
-- Ripetibile. Le partite gia' salvate restano senza dettaglio dei marcatori.

alter table fusball.partite add column if not exists marcatori text not null default '';
alter table fusball.partite_giocatori add column if not exists pos smallint;

create or replace function fusball.salva_partita(p_token uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti; v uuid; g jsonb; gid uuid; i int; mk text;
begin
  u := fusball._perm(p_token, 'partite');
  select id into v from fusball.partite where client_id = (p->>'client_id')::uuid;
  if v is not null then return v; end if;   -- gia' salvata (ritrasmissione dalla coda offline)
  if jsonb_array_length(p->'giocatori') <> 4 then raise exception 'giocatori_non_validi'; end if;
  mk := coalesce(p->>'marcatori', '');
  if mk <> '' then
    if mk !~ '^[0-3][PA][ng](,[0-3][PA][ng])*$'
       or array_length(string_to_array(mk, ','), 1) <> length(coalesce(p->>'sequenza_gol', '')) then
      raise exception 'marcatori_non_validi';
    end if;
  end if;
  insert into fusball.partite (client_id, giocata_il, obiettivo, scarto, timer_sec, durata_sec,
                       gol_a, gol_b, sequenza_gol, marcatori, motivo_fine, creata_da, creata_da_nome)
  values ((p->>'client_id')::uuid, (p->>'giocata_il')::timestamptz, (p->>'obiettivo')::int,
          (p->>'scarto')::int, nullif(p->>'timer_sec','')::int, (p->>'durata_sec')::int,
          (p->>'gol_a')::int, (p->>'gol_b')::int, coalesce(p->>'sequenza_gol',''), mk, p->>'motivo_fine',
          u.id, u.nome)
  returning id into v;
  for g, i in select e, (o - 1)::int from jsonb_array_elements(p->'giocatori') with ordinality as t(e, o) loop
    if trim(coalesce(g->>'nome','')) = '' or trim(coalesce(g->>'cognome','')) = '' then
      raise exception 'giocatori_non_validi';
    end if;
    insert into fusball.giocatori (nome, cognome)
    values (trim(g->>'nome'), trim(g->>'cognome'))
    on conflict (lower(nome), lower(cognome)) do update set attivo = true
    returning id into gid;
    insert into fusball.partite_giocatori (partita_id, giocatore_id, squadra, pos)
    values (v, gid, g->>'squadra', i);
  end loop;
  return v;
end $$;

-- correggere il punteggio a mano azzera anche il dettaglio dei marcatori
create or replace function fusball.modifica_partita(p_token uuid, p_id uuid, p_gol_a int, p_gol_b int) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti;
begin
  u := fusball._utente(p_token);
  perform fusball._puo_correggere(u, p_id);
  if p_gol_a = p_gol_b then raise exception 'pareggio_non_valido'; end if;
  update fusball.partite set gol_a = p_gol_a, gol_b = p_gol_b, sequenza_gol = '', marcatori = '', modificato_il = now()
  where id = p_id;
end $$;

notify pgrst, 'reload schema';
