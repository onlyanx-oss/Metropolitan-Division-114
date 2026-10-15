-- =====================================================================
--  Metropolitan Division · Base de datos de cuentas (Supabase / Postgres)
--  Pégalo entero en Supabase > SQL Editor > New query > Run.
--  Cambia 'METRO114' por el código de registro que quieras ANTES de ejecutarlo.
-- =====================================================================

-- 1) Tablas -----------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text unique not null,
  full_name     text not null,
  division_rank text not null default 'Aspirante'
                check (division_rank in ('Comandante','Subcomandante','Supervisor','Oficial','Aspirante')),
  is_admin      boolean not null default false,
  created_at    timestamptz not null default now()
);

create table if not exists public.app_settings (
  key   text primary key,
  value text not null
);

insert into public.app_settings (key, value)
values ('registration_code', 'METRO114')
on conflict (key) do nothing;

-- 2) Seguridad por filas (RLS) ----------------------------------------
alter table public.profiles     enable row level security;
alter table public.app_settings enable row level security;   -- sin políticas: nadie la lee desde la web

-- Funciones auxiliares (leen el perfil del usuario que hace la petición)
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.is_command()
returns boolean language sql security definer set search_path = public stable as $$
  select coalesce((select division_rank in ('Comandante','Subcomandante')
                   from public.profiles where id = auth.uid()), false)
$$;

drop policy if exists profiles_select       on public.profiles;
drop policy if exists profiles_update_admin on public.profiles;

-- Cada miembro ve su propio perfil; los administradores y la comandancia ven todos.
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.is_command());

-- SOLO los administradores pueden modificar perfiles (y solo la columna del rango, ver permisos).
create policy profiles_update_admin on public.profiles
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 3) Permisos de columnas ---------------------------------------------
revoke all on public.profiles     from anon, authenticated;
revoke all on public.app_settings from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (division_rank) on public.profiles to authenticated;
-- Nadie puede crear ni borrar perfiles desde la web: los crea el disparador de abajo.
-- is_admin solo se cambia desde el SQL Editor (ver instrucciones).

-- 4) Alta de cuentas: valida el código de la División y crea el perfil ---
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  code  text;
  uname text;
  fname text;
begin
  select value into code from public.app_settings where key = 'registration_code';
  if coalesce(new.raw_user_meta_data->>'code', '') <> coalesce(code, '') then
    raise exception 'Código de la División incorrecto';
  end if;

  uname := lower(trim(coalesce(new.raw_user_meta_data->>'username', '')));
  fname := trim(coalesce(new.raw_user_meta_data->>'full_name', ''));
  if uname = '' or fname = '' then
    raise exception 'Faltan datos';
  end if;

  insert into public.profiles (id, username, full_name) values (new.id, uname, fname);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
--  DESPUÉS de registrarte en la web, hazte administrador ejecutando esto
--  (cambia tu_usuario por tu usuario, en minúsculas):
--
--    update public.profiles set is_admin = true where username = 'tu_usuario';
--
--  Para cambiar el código de registro en cualquier momento:
--
--    update public.app_settings set value = 'NUEVO_CODIGO' where key = 'registration_code';
-- =====================================================================
