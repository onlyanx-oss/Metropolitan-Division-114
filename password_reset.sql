-- =====================================================================
--  Restablecer contraseña con código de la comandancia
--  Ejecútalo en Supabase > SQL Editor > New query > Run
--  (DESPUÉS de schema.sql; se puede ejecutar más de una vez sin problema).
--
--  Cómo funciona:
--   · Un Comandante, Subcomandante o administrador genera un código para un
--     usuario desde la pestaña Cuentas de la web.
--   · El código vale 1 hora, se usa una sola vez y se bloquea tras 5 fallos.
--   · El miembro lo escribe en "¿Olvidaste la contraseña?" y pone una nueva.
--   · Un Comandante/Subcomandante solo puede generar códigos para usuarios de
--     RANGO INFERIOR al suyo y que no sean administradores. Los administradores
--     pueden para cualquiera. (Así nadie puede apoderarse de una cuenta superior.)
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.password_resets (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  code_hash  text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz,
  attempts   int not null default 0
);

alter table public.password_resets enable row level security;   -- sin políticas: inaccesible desde la web
revoke all on public.password_resets from anon, authenticated;

-- ---------------------------------------------------------------------
-- Generar código (solo comandancia / administradores)
-- ---------------------------------------------------------------------
create or replace function public.create_reset_code(p_username text)
returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  caller   public.profiles%rowtype;
  tgt      public.profiles%rowtype;
  ranks    text[] := array['Aspirante','Oficial','Supervisor','Subcomandante','Comandante'];
  alphabet text   := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes    bytea;
  code     text   := '';
  i        int;
begin
  select * into caller from public.profiles where id = auth.uid();
  if not found then
    raise exception 'No autorizado';
  end if;
  if not (caller.is_admin or caller.division_rank in ('Comandante','Subcomandante')) then
    raise exception 'No autorizado';
  end if;

  select * into tgt from public.profiles where username = lower(trim(p_username));
  if not found then
    raise exception 'Usuario no encontrado';
  end if;
  if tgt.id = caller.id then
    raise exception 'No puedes generar un código para tu propia cuenta';
  end if;

  if not caller.is_admin then
    if tgt.is_admin
       or array_position(ranks, tgt.division_rank) >= array_position(ranks, caller.division_rank) then
      raise exception 'Solo puedes restablecer la contraseña de usuarios de rango inferior al tuyo';
    end if;
  end if;

  -- invalida los códigos anteriores sin usar de ese usuario
  update public.password_resets set used_at = now()
   where user_id = tgt.id and used_at is null;

  bytes := gen_random_bytes(8);
  for i in 0..7 loop
    code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;

  insert into public.password_resets (user_id, code_hash, created_by, expires_at)
  values (tgt.id, encode(digest(code, 'sha256'), 'hex'), caller.id, now() + interval '1 hour');

  return substr(code, 1, 4) || '-' || substr(code, 5, 4);
end $$;

revoke all on function public.create_reset_code(text) from public, anon;
grant execute on function public.create_reset_code(text) to authenticated;

-- ---------------------------------------------------------------------
-- Cambiar la contraseña con el código (lo usa el miembro, sin sesión)
-- Devuelve true si se cambió y false si el código no sirve.
-- ---------------------------------------------------------------------
create or replace function public.reset_password_with_code(p_username text, p_code text, p_new_password text)
returns boolean
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  tgt   public.profiles%rowtype;
  r     public.password_resets%rowtype;
  clean text;
begin
  if length(coalesce(p_new_password, '')) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres';
  end if;

  select * into tgt from public.profiles where username = lower(trim(p_username));
  if not found then
    return false;
  end if;

  select * into r from public.password_resets
   where user_id = tgt.id and used_at is null and expires_at > now()
   order by id desc limit 1
   for update;
  if not found then
    return false;
  end if;

  if r.attempts >= 5 then
    update public.password_resets set used_at = now() where id = r.id;
    return false;
  end if;

  clean := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if r.code_hash <> encode(digest(clean, 'sha256'), 'hex') then
    update public.password_resets set attempts = attempts + 1 where id = r.id;
    return false;
  end if;

  update auth.users
     set encrypted_password = crypt(p_new_password, gen_salt('bf')),
         updated_at = now()
   where id = tgt.id;

  update public.password_resets set used_at = now() where id = r.id;

  -- cierra las sesiones abiertas de esa cuenta
  begin
    delete from auth.sessions where user_id = tgt.id;
  exception when others then
    null;
  end;

  return true;
end $$;

revoke all on function public.reset_password_with_code(text, text, text) from public;
grant execute on function public.reset_password_with_code(text, text, text) to anon, authenticated;
