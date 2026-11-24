-- Fusball v1.0 - schema Postgres (schema dedicato "fusball" nel progetto Supabase condiviso)
-- Eseguire UNA volta nello SQL Editor di Supabase, dopo aver sostituito il PIN iniziale (riga "PIN INIZIALE").
-- Poi: Settings > API > "Exposed schemas": aggiungere "fusball" e salvare.
-- Si scrive SOLO tramite funzioni security definer. L'anon legge solo giocatori, partite, partite_giocatori.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists fusball;

-- TABELLE
create table if not exists fusball.giocatori (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cognome text not null,
  soprannome text,
  attivo boolean not null default true,
  creato_il timestamptz not null default now()
);
create unique index if not exists giocatori_nome_uq on fusball.giocatori (lower(nome), lower(cognome));

create table if not exists fusball.partite (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,                 -- idempotenza (coda offline)
  giocata_il timestamptz not null,
  obiettivo int not null check (obiettivo between 6 and 10),
  scarto int not null default 2 check (scarto between 1 and 3),
  timer_sec int check (timer_sec in (300, 600)),
  durata_sec int not null check (durata_sec >= 0),
  gol_a int not null check (gol_a between 0 and 30),
  gol_b int not null check (gol_b between 0 and 30),
  sequenza_gol text not null default '',          -- 'A'/'B' in ordine di gol; '' se punteggio corretto a mano
  motivo_fine text not null check (motivo_fine in ('obiettivo','timer','golden','manuale')),
  eliminata boolean not null default false,       -- soft delete
  creato_il timestamptz not null default now(),
  modificato_il timestamptz not null default now()
);
create index if not exists partite_data_ix on fusball.partite (giocata_il desc);

create table if not exists fusball.partite_giocatori (
  partita_id uuid not null references fusball.partite(id) on delete cascade,
  giocatore_id uuid not null references fusball.giocatori(id),
  squadra char(1) not null check (squadra in ('A','B')),
  primary key (partita_id, giocatore_id)
);

create table if not exists fusball.impostazioni (
  id int primary key default 1 check (id = 1),
  pin_hash text not null
);
create table if not exists fusball.sessioni (
  token uuid primary key default gen_random_uuid(),
  creata_il timestamptz not null default now(),
  scade_il timestamptz not null default now() + interval '60 days'
);
create table if not exists fusball.pin_tentativi (ts timestamptz not null default now());

-- PIN INIZIALE: sostituire CAMBIA_IL_PIN con 4-6 cifre PRIMA di eseguire, poi cambiarlo dall'app (Impostazioni > Sicurezza).
-- Non salvare il PIN reale in nessun file del repository.
insert into fusball.impostazioni (id, pin_hash)
values (1, extensions.crypt('CAMBIA_IL_PIN', extensions.gen_salt('bf')))
on conflict (id) do nothing;

-- RLS E PERMESSI
alter table fusball.giocatori enable row level security;
alter table fusball.partite enable row level security;
alter table fusball.partite_giocatori enable row level security;
alter table fusball.impostazioni enable row level security;
alter table fusball.sessioni enable row level security;
alter table fusball.pin_tentativi enable row level security;

drop policy if exists lettura on fusball.giocatori;
drop policy if exists lettura on fusball.partite;
drop policy if exists lettura on fusball.partite_giocatori;
create policy lettura on fusball.giocatori for select to anon using (true);
create policy lettura on fusball.partite for select to anon using (true);
create policy lettura on fusball.partite_giocatori for select to anon using (true);

revoke all on all tables in schema fusball from anon, authenticated;
grant usage on schema fusball to anon;
grant select on fusball.giocatori, fusball.partite, fusball.partite_giocatori to anon;

-- FUNZIONI
create or replace function fusball._ok(p_token uuid) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  if not exists (select 1 from fusball.sessioni where token = p_token and scade_il > now()) then
    raise exception 'non_autorizzato';
  end if;
end $$;

-- ritorna il token, oppure null se il PIN è errato
create or replace function fusball.login(p_pin text) returns uuid
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare v uuid;
begin
  if (select count(*) from fusball.pin_tentativi where ts > now() - interval '10 minutes') >= 5 then
    raise exception 'troppi_tentativi';
  end if;
  if exists (select 1 from fusball.impostazioni where pin_hash = crypt(p_pin, pin_hash)) then
    delete from fusball.sessioni where scade_il < now();
    delete from fusball.pin_tentativi where ts < now() - interval '1 day';
    insert into fusball.sessioni default values returning token into v;
    return v;
  end if;
  insert into fusball.pin_tentativi default values;
  return null;
end $$;

create or replace function fusball.salva_partita(p_token uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare v uuid; g jsonb; gid uuid; n int;
begin
  perform fusball._ok(p_token);
  select id into v from fusball.partite where client_id = (p->>'client_id')::uuid;
  if v is not null then return v; end if;   -- già salvata (ritrasmissione dalla coda offline)
  n := jsonb_array_length(p->'giocatori');
  if n <> 4 then raise exception 'giocatori_non_validi'; end if;
  insert into fusball.partite (client_id, giocata_il, obiettivo, scarto, timer_sec, durata_sec,
                       gol_a, gol_b, sequenza_gol, motivo_fine)
  values ((p->>'client_id')::uuid, (p->>'giocata_il')::timestamptz, (p->>'obiettivo')::int,
          (p->>'scarto')::int, nullif(p->>'timer_sec','')::int, (p->>'durata_sec')::int,
          (p->>'gol_a')::int, (p->>'gol_b')::int, coalesce(p->>'sequenza_gol',''), p->>'motivo_fine')
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
begin
  perform fusball._ok(p_token);
  update fusball.partite set gol_a = p_gol_a, gol_b = p_gol_b, sequenza_gol = '', modificato_il = now()
  where id = p_id;
end $$;

create or replace function fusball.annulla_partita(p_token uuid, p_id uuid, p_annulla boolean default true) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._ok(p_token);
  update fusball.partite set eliminata = p_annulla, modificato_il = now() where id = p_id;
end $$;

create or replace function fusball.upsert_giocatore(p_token uuid, p_nome text, p_cognome text, p_soprannome text default null) returns uuid
language plpgsql security definer set search_path = fusball, extensions, public as $$
declare v uuid;
begin
  perform fusball._ok(p_token);
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
  perform fusball._ok(p_token);
  update fusball.giocatori set attivo = p_attivo where id = p_id;
end $$;

create or replace function fusball.cambia_pin(p_token uuid, p_vecchio text, p_nuovo text) returns boolean
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._ok(p_token);
  if p_nuovo !~ '^[0-9]{4,6}$' then raise exception 'pin_non_valido'; end if;
  if not exists (select 1 from fusball.impostazioni where pin_hash = crypt(p_vecchio, pin_hash)) then return false; end if;
  update fusball.impostazioni set pin_hash = crypt(p_nuovo, gen_salt('bf')) where id = 1;
  return true;
end $$;

create or replace function fusball.logout_tutti(p_token uuid) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._ok(p_token);
  delete from fusball.sessioni;
end $$;

-- Permessi funzioni: di default Postgres concede execute a PUBLIC, quindi lo si toglie prima
revoke execute on all functions in schema fusball from public, anon, authenticated;
grant execute on function fusball.login(text), fusball.salva_partita(uuid, jsonb),
  fusball.modifica_partita(uuid, uuid, int, int), fusball.annulla_partita(uuid, uuid, boolean),
  fusball.upsert_giocatore(uuid, text, text, text), fusball.imposta_giocatore_attivo(uuid, uuid, boolean),
  fusball.cambia_pin(uuid, text, text), fusball.logout_tutti(uuid) to anon;
