-- Security hardening after code review (2026-08-17).
--
-- 1. link_tokens: records which user created each Plaid Link token so the
--    plaid-link "complete" action can verify the token belongs to the caller.
-- 2. Foreign keys that clients can write (account_id, category_id,
--    plaid_item_id) must point at rows the user is allowed to use — the old
--    policies only checked user_id, letting a client attach rows to other
--    users' accounts/items by guessing UUIDs.

-- ------------------------------------------------------------- link_tokens
create table link_tokens (
  link_token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
-- Service role only: RLS on with no policies + no client grants.
alter table link_tokens enable row level security;
revoke all on link_tokens from anon, authenticated;

-- ------------------------------------------------------------ transactions
drop policy txn_all on transactions;
create policy txn_select on transactions for select using (auth.uid() = user_id);
create policy txn_delete on transactions for delete using (auth.uid() = user_id);
create policy txn_insert on transactions for insert with check (
  auth.uid() = user_id
  and exists (select 1 from accounts a
              where a.id = account_id and a.user_id = auth.uid())
  and (category_id is null or exists (
        select 1 from categories c
        where c.id = category_id
          and (c.user_id is null or c.user_id = auth.uid())))
);
create policy txn_update on transactions for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (select 1 from accounts a
                where a.id = account_id and a.user_id = auth.uid())
    and (category_id is null or exists (
          select 1 from categories c
          where c.id = category_id
            and (c.user_id is null or c.user_id = auth.uid())))
  );

-- ---------------------------------------------------------------- accounts
drop policy acc_all on accounts;
create policy acc_select on accounts for select using (auth.uid() = user_id);
create policy acc_delete on accounts for delete using (auth.uid() = user_id);
create policy acc_insert on accounts for insert with check (
  auth.uid() = user_id
  and (plaid_item_id is null or exists (
        select 1 from plaid_items p
        where p.id = plaid_item_id and p.user_id = auth.uid()))
);
create policy acc_update on accounts for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (plaid_item_id is null or exists (
          select 1 from plaid_items p
          where p.id = plaid_item_id and p.user_id = auth.uid()))
  );

-- ----------------------------------------------------------------- budgets
drop policy bud_all on budgets;
create policy bud_select on budgets for select using (auth.uid() = user_id);
create policy bud_delete on budgets for delete using (auth.uid() = user_id);
create policy bud_insert on budgets for insert with check (
  auth.uid() = user_id
  and exists (select 1 from categories c
              where c.id = category_id
                and (c.user_id is null or c.user_id = auth.uid()))
);
create policy bud_update on budgets for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (select 1 from categories c
                where c.id = category_id
                  and (c.user_id is null or c.user_id = auth.uid()))
  );
