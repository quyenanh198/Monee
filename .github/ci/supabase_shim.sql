-- Minimal Supabase emulation so the migrations apply on vanilla Postgres in
-- CI. Mirrors only what the migrations reference: the auth schema, the
-- client roles, and the realtime publication.

create schema if not exists auth;

create table auth.users (
  id uuid primary key default gen_random_uuid()
);

create function auth.uid() returns uuid
language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

do $$ begin
  create role anon nologin;
  exception when duplicate_object then null;
end $$;
do $$ begin
  create role authenticated nologin;
  exception when duplicate_object then null;
end $$;
do $$ begin
  create role service_role nologin bypassrls;
  exception when duplicate_object then null;
end $$;

create publication supabase_realtime;
