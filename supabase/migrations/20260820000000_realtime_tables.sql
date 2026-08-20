-- Live refresh: put the remaining user-data tables on the realtime
-- publication so the app can invalidate caches when rows change
-- (transactions was added in the init migration).
--
-- plaid_items is deliberately NOT published: realtime change payloads
-- carry every column of the row and do not enforce column-level grants,
-- which would leak access_token to the client.

do $$
declare
  t text;
begin
  foreach t in array array[
    'accounts', 'budgets', 'goals', 'categories', 'rules',
    'balance_snapshots'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
