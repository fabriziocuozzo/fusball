-- Fusball v1.0 - modifica di nome, cognome e soprannome di un giocatore
-- Da eseguire UNA volta nello SQL Editor se schema.sql e' gia' stato eseguito (le installazioni nuove lo hanno gia' in schema.sql).
create or replace function fusball.modifica_giocatore(p_token uuid, p_id uuid, p_nome text, p_cognome text, p_soprannome text default null) returns void
language plpgsql security definer set search_path = fusball, extensions, public as $$
begin
  perform fusball._ok(p_token);
  if trim(coalesce(p_nome,'')) = '' or trim(coalesce(p_cognome,'')) = '' then raise exception 'giocatori_non_validi'; end if;
  if exists (select 1 from fusball.giocatori where id <> p_id and lower(nome) = lower(trim(p_nome)) and lower(cognome) = lower(trim(p_cognome))) then
    raise exception 'giocatore_esistente';
  end if;
  update fusball.giocatori set nome = trim(p_nome), cognome = trim(p_cognome), soprannome = nullif(trim(p_soprannome), '') where id = p_id;
end $$;

revoke execute on function fusball.modifica_giocatore(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function fusball.modifica_giocatore(uuid, uuid, text, text, text) to anon;
