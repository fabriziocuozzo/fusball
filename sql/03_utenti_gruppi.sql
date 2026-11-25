-- Fusball v2.0 - utenti con nome e PIN, gruppi di permessi
-- Da eseguire UNA volta nello SQL Editor di Supabase, dopo schema.sql (e 02, gia' inclusa in schema.sql).
-- Cosa fa:
--   * crea i gruppi admin / normale / lettura e la tabella utenti
--   * trasforma il PIN unico attuale nell'utente admin "Fabrizio Cuozzo" (stesso PIN di oggi)
--   * ogni partita ricorda chi l'ha inserita
--   * ogni funzione di scrittura controlla il permesso del gruppo
-- Ripetibile: si puo' rieseguire senza errori. Dopo l'esecuzione:  notify pgrst, 'reload schema';

-- ============ TABELLE ============
create table if not exists fusball.gruppi (
  id text primary key,
  nome text not null,
  permessi jsonb not null default '{}'
);
-- permessi: partite (avviare/salvare), storico (correggere qualsiasi partita), giocatori (gestione), utenti (gestione),
--           recente_min (minuti entro cui si corregge la PROPRIA partita appena salvata)
insert into fusball.gruppi (id, nome, permessi) values
  ('admin',   'Amministratore', '{"partite":true,"storico":true,"giocatori":true,"utenti":true}'),
  ('normale', 'Normale',        '{"partite":true,"recente_min":3}'),
  ('lettura', 'Solo lettura',   '{}')
on conflict (id) do nothing;

create table if not exists fusball.utenti (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(trim(nome)) > 0),
  pin_hash text not null,
  gruppo text not null references fusball.gruppi(id),
  attivo boolean not null default true,
  creato_il timestamptz not null default now()
);
create unique index if not exists utenti_nome_uq on fusball.utenti (lower(nome));

-- il PIN unico di v1 diventa l'utente admin
do $$
begin
  if to_regclass('fusball.impostazioni') is not null then
    insert into fusball.utenti (nome, pin_hash, gruppo)
    select 'Fabrizio Cuozzo', pin_hash, 'admin' from fusball.impostazioni where id = 1
    on conflict do nothing;
    drop table fusball.impostazioni;
  end if;
end $$;

alter table fusball.sessioni add column if not exists utente_id uuid references fusball.utenti(id) on delete cascade;
delete from fusball.sessioni where utente_id is null;          -- le vecchie sessioni senza utente non valgono piu'
alter table fusball.partite add column if not exists creata_da uuid references fusball.utenti(id) on delete set null;
alter table fusball.partite add column if not exists creata_da_nome text;
alter table fusball.pin_tentativi add column if not exists nome text;

alter table fusball.gruppi enable row level security;
alter table fusball.utenti enable row level security;
revoke all on all tables in schema fusball from anon, authenticated;
grant select on fusball.giocatori, fusball.partite, fusball.partite_giocatori to anon;

-- ============ FUNZIONI INTERNE (non raggiungibili dall'esterno) ============
drop function if exists fusball.login(text);

create or replace function fusball._utente(p_token uuid) returns fusball.utenti
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti;
begin
  select ut.* into u from fusball.sessioni s join fusball.utenti ut on ut.id = s.utente_id
   where s.token = p_token and s.scade_il > now() and ut.attivo;
  if u.id is null then raise exception 'non_autorizzato'; end if;
  return u;
end $$;

create or replace function fusball._perm(p_token uuid, p_perm text) returns fusball.utenti
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti;
begin
  u := fusball._utente(p_token);
  if not coalesce((select (permessi ->> p_perm)::boolean from fusball.gruppi where id = u.gruppo), false) then
    raise exception 'permesso_negato';
  end if;
  return u;
end $$;

create or replace function fusball._profilo(u fusball.utenti) returns jsonb
language sql stable security definer set search_path = fusball, public as $$
  select jsonb_build_object('nome', u.nome, 'gruppo', u.gruppo,
    'permessi', coalesce((select permessi from fusball.gruppi where id = u.gruppo), '{}'::jsonb))
$$;

-- correzione di una partita gia' salvata: admin sempre; gli altri solo la propria, entro "recente_min" minuti
create or replace function fusball._puo_correggere(u fusball.utenti, p_id uuid) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare perm jsonb; mins int;
begin
  select permessi into perm from fusball.gruppi where id = u.gruppo;
  if coalesce((perm ->> 'storico')::boolean, false) then return; end if;
  mins := coalesce((perm ->> 'recente_min')::int, 0);
  if mins > 0 and exists (select 1 from fusball.partite
                          where id = p_id and creata_da = u.id and creato_il > now() - make_interval(mins => mins)) then
    return;
  end if;
  raise exception 'permesso_negato';
end $$;

-- ============ ACCESSO ============
-- ritorna {token, nome, gruppo, permessi}, oppure null se nome o PIN sono errati
create or replace function fusball.login(p_nome text, p_pin text) returns jsonb
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti; v uuid; n text := lower(trim(coalesce(p_nome, '')));
begin
  if (select count(*) from fusball.pin_tentativi where ts > now() - interval '10 minutes') >= 200
     or (select count(*) from fusball.pin_tentativi where nome = n and ts > now() - interval '10 minutes') >= 5 then
    raise exception 'troppi_tentativi';
  end if;
  select * into u from fusball.utenti where lower(nome) = n and attivo;
  if u.id is not null and u.pin_hash = crypt(coalesce(p_pin, ''), u.pin_hash) then
    delete from fusball.sessioni where scade_il < now();
    delete from fusball.pin_tentativi where ts < now() - interval '1 day' or nome = n;
    insert into fusball.sessioni (utente_id) values (u.id) returning token into v;
    return jsonb_build_object('token', v) || fusball._profilo(u);
  end if;
  perform crypt(coalesce(p_pin, ''), gen_salt('bf'));      -- stesso tempo anche se il nome non esiste
  insert into fusball.pin_tentativi (nome) values (n);
  return null;
end $$;

create or replace function fusball.mio_profilo(p_token uuid) returns jsonb
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  return fusball._profilo(fusball._utente(p_token));
end $$;

create or replace function fusball.cambia_pin(p_token uuid, p_vecchio text, p_nuovo text) returns boolean
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti; n text;
begin
  u := fusball._utente(p_token);
  n := lower(u.nome);
  if p_nuovo !~ '^[0-9]{4,6}$' then raise exception 'pin_non_valido'; end if;
  if (select count(*) from fusball.pin_tentativi where nome = n and ts > now() - interval '10 minutes') >= 5 then
    raise exception 'troppi_tentativi';
  end if;
  if u.pin_hash <> crypt(coalesce(p_vecchio, ''), u.pin_hash) then
    insert into fusball.pin_tentativi (nome) values (n);
    return false;
  end if;
  update fusball.utenti set pin_hash = crypt(p_nuovo, gen_salt('bf')) where id = u.id;
  return true;
end $$;

create or replace function fusball.logout_tutti(p_token uuid) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._perm(p_token, 'utenti');
  delete from fusball.sessioni;
end $$;

-- ============ PARTITE ============
create or replace function fusball.salva_partita(p_token uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti; v uuid; g jsonb; gid uuid;
begin
  u := fusball._perm(p_token, 'partite');
  select id into v from fusball.partite where client_id = (p->>'client_id')::uuid;
  if v is not null then return v; end if;   -- gia' salvata (ritrasmissione dalla coda offline)
  if jsonb_array_length(p->'giocatori') <> 4 then raise exception 'giocatori_non_validi'; end if;
  insert into fusball.partite (client_id, giocata_il, obiettivo, scarto, timer_sec, durata_sec,
                       gol_a, gol_b, sequenza_gol, motivo_fine, creata_da, creata_da_nome)
  values ((p->>'client_id')::uuid, (p->>'giocata_il')::timestamptz, (p->>'obiettivo')::int,
          (p->>'scarto')::int, nullif(p->>'timer_sec','')::int, (p->>'durata_sec')::int,
          (p->>'gol_a')::int, (p->>'gol_b')::int, coalesce(p->>'sequenza_gol',''), p->>'motivo_fine',
          u.id, u.nome)
  returning id into v;
  for g in select * from jsonb_array_elements(p->'giocatori') loop
    if trim(coalesce(g->>'nome','')) = '' or trim(coalesce(g->>'cognome','')) = '' then
      raise exception 'giocatori_non_validi';
    end if;
    insert into fusball.giocatori (nome, cognome)
    values (trim(g->>'nome'), trim(g->>'cognome'))
    on conflict (lower(nome), lower(cognome)) do update set attivo = true
    returning id into gid;
    insert into fusball.partite_giocatori (partita_id, giocatore_id, squadra)
    values (v, gid, g->>'squadra');
  end loop;
  return v;
end $$;

create or replace function fusball.modifica_partita(p_token uuid, p_id uuid, p_gol_a int, p_gol_b int) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti;
begin
  u := fusball._utente(p_token);
  perform fusball._puo_correggere(u, p_id);
  if p_gol_a = p_gol_b then raise exception 'pareggio_non_valido'; end if;
  update fusball.partite set gol_a = p_gol_a, gol_b = p_gol_b, sequenza_gol = '', modificato_il = now()
  where id = p_id;
end $$;

create or replace function fusball.annulla_partita(p_token uuid, p_id uuid, p_annulla boolean default true) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare u fusball.utenti;
begin
  u := fusball._utente(p_token);
  perform fusball._puo_correggere(u, p_id);
  update fusball.partite set eliminata = p_annulla, modificato_il = now() where id = p_id;
end $$;

-- ============ GIOCATORI (solo admin) ============
create or replace function fusball.upsert_giocatore(p_token uuid, p_nome text, p_cognome text, p_soprannome text default null) returns uuid
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare v uuid;
begin
  perform fusball._perm(p_token, 'giocatori');
  if trim(coalesce(p_nome,'')) = '' or trim(coalesce(p_cognome,'')) = '' then raise exception 'giocatori_non_validi'; end if;
  insert into fusball.giocatori (nome, cognome, soprannome)
  values (trim(p_nome), trim(p_cognome), nullif(trim(p_soprannome), ''))
  on conflict (lower(nome), lower(cognome)) do update
    set soprannome = excluded.soprannome, attivo = true
  returning id into v;
  return v;
end $$;

create or replace function fusball.imposta_giocatore_attivo(p_token uuid, p_id uuid, p_attivo boolean) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._perm(p_token, 'giocatori');
  update fusball.giocatori set attivo = p_attivo where id = p_id;
end $$;

create or replace function fusball.modifica_giocatore(p_token uuid, p_id uuid, p_nome text, p_cognome text, p_soprannome text default null) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._perm(p_token, 'giocatori');
  if trim(coalesce(p_nome,'')) = '' or trim(coalesce(p_cognome,'')) = '' then raise exception 'giocatori_non_validi'; end if;
  if exists (select 1 from fusball.giocatori where id <> p_id and lower(nome) = lower(trim(p_nome)) and lower(cognome) = lower(trim(p_cognome))) then
    raise exception 'giocatore_esistente';
  end if;
  update fusball.giocatori set nome = trim(p_nome), cognome = trim(p_cognome), soprannome = nullif(trim(p_soprannome), '') where id = p_id;
end $$;

-- ============ GESTIONE UTENTI (solo admin) ============
create or replace function fusball.elenco_utenti(p_token uuid) returns jsonb
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._perm(p_token, 'utenti');
  return jsonb_build_object(
    'utenti', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', nome, 'gruppo', gruppo, 'attivo', attivo) order by lower(nome)), '[]'::jsonb) from fusball.utenti),
    'gruppi', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome), '[]'::jsonb) from fusball.gruppi));
end $$;

create or replace function fusball.crea_utente(p_token uuid, p_nome text, p_pin text, p_gruppo text) returns uuid
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare v uuid;
begin
  perform fusball._perm(p_token, 'utenti');
  if length(trim(coalesce(p_nome, ''))) = 0 then raise exception 'nome_non_valido'; end if;
  if p_pin !~ '^[0-9]{4,6}$' then raise exception 'pin_non_valido'; end if;
  if not exists (select 1 from fusball.gruppi where id = p_gruppo) then raise exception 'gruppo_non_valido'; end if;
  begin
    insert into fusball.utenti (nome, pin_hash, gruppo)
    values (trim(p_nome), crypt(p_pin, gen_salt('bf')), p_gruppo) returning id into v;
  exception when unique_violation then
    raise exception 'utente_esistente';
  end;
  return v;
end $$;

create or replace function fusball.modifica_utente(p_token uuid, p_id uuid, p_gruppo text, p_attivo boolean) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._perm(p_token, 'utenti');
  if not exists (select 1 from fusball.gruppi where id = p_gruppo) then raise exception 'gruppo_non_valido'; end if;
  update fusball.utenti set gruppo = p_gruppo, attivo = p_attivo where id = p_id;
  if not p_attivo then delete from fusball.sessioni where utente_id = p_id; end if;
  if not exists (select 1 from fusball.utenti where gruppo = 'admin' and attivo) then
    raise exception 'serve_un_admin';       -- annulla anche la modifica appena fatta
  end if;
end $$;

create or replace function fusball.reimposta_pin_utente(p_token uuid, p_id uuid, p_pin text) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare n text;
begin
  perform fusball._perm(p_token, 'utenti');
  if p_pin !~ '^[0-9]{4,6}$' then raise exception 'pin_non_valido'; end if;
  update fusball.utenti set pin_hash = crypt(p_pin, gen_salt('bf')) where id = p_id returning lower(nome) into n;
  delete from fusball.sessioni where utente_id = p_id;
  delete from fusball.pin_tentativi where nome = n;
end $$;

-- ============ PERMESSI DI ESECUZIONE ============
drop function if exists fusball._ok(uuid);
revoke execute on all functions in schema fusball from public, anon, authenticated;
grant execute on function
  fusball.login(text, text), fusball.mio_profilo(uuid), fusball.cambia_pin(uuid, text, text), fusball.logout_tutti(uuid),
  fusball.salva_partita(uuid, jsonb), fusball.modifica_partita(uuid, uuid, int, int), fusball.annulla_partita(uuid, uuid, boolean),
  fusball.upsert_giocatore(uuid, text, text, text), fusball.imposta_giocatore_attivo(uuid, uuid, boolean),
  fusball.modifica_giocatore(uuid, uuid, text, text, text),
  fusball.elenco_utenti(uuid), fusball.crea_utente(uuid, text, text, text),
  fusball.modifica_utente(uuid, uuid, text, boolean), fusball.reimposta_pin_utente(uuid, uuid, text)
to anon;

notify pgrst, 'reload schema';
