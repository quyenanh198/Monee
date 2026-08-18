-- Feature pack (2026-08-18): categorization rules, balance snapshots (net
-- worth), savings goals, split transactions + notes/tags, budget rollover.

-- ------------------------------------------------------------------- rules
-- Auto-categorization: applied by syncItem() to newly added Plaid
-- transactions that have no category yet.
create table rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  pattern text not null check (length(pattern) between 1 and 100),
  match_field text not null default 'any' check (match_field in ('merchant','description','any')),
  category_id uuid not null references categories (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index idx_rules_user on rules (user_id);

alter table rules enable row level security;
create policy rule_select on rules for select using (auth.uid() = user_id);
create policy rule_delete on rules for delete using (auth.uid() = user_id);
create policy rule_insert on rules for insert with check (
  auth.uid() = user_id
  and exists (select 1 from categories c
              where c.id = category_id
                and (c.user_id is null or c.user_id = auth.uid()))
);
create policy rule_update on rules for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (select 1 from categories c
                where c.id = category_id
                  and (c.user_id is null or c.user_id = auth.uid()))
  );

-- ------------------------------------------------------- balance_snapshots
-- One row per user per day, written by the plaid-sync Edge Function
-- (service role). Clients read only.
create table balance_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  date date not null,
  total numeric(14,2) not null,
  unique (user_id, date)
);
create index idx_snap_user_date on balance_snapshots (user_id, date desc);

alter table balance_snapshots enable row level security;
create policy snap_select on balance_snapshots for select using (auth.uid() = user_id);
-- no insert/update/delete policies: service role only

-- -------------------------------------------------------------------- goals
-- Savings goals. Linked to an account (progress = account balance) or
-- tracked manually via saved_amount.
create table goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  target_amount numeric(14,2) not null check (target_amount > 0),
  saved_amount numeric(14,2) not null default 0 check (saved_amount >= 0),
  account_id uuid references accounts (id) on delete set null,
  target_date date,
  created_at timestamptz not null default now()
);

alter table goals enable row level security;
create policy goal_select on goals for select using (auth.uid() = user_id);
create policy goal_delete on goals for delete using (auth.uid() = user_id);
create policy goal_insert on goals for insert with check (
  auth.uid() = user_id
  and (account_id is null or exists (
        select 1 from accounts a
        where a.id = goals.account_id and a.user_id = auth.uid()))
);
create policy goal_update on goals for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (account_id is null or exists (
          select 1 from accounts a
          where a.id = goals.account_id and a.user_id = auth.uid()))
  );

-- ------------------------------------------- transactions: split/note/tags
alter table transactions add column note text;
alter table transactions add column tags text[] not null default '{}';
alter table transactions add column parent_txn_id uuid
  references transactions (id) on delete cascade;
create index idx_txn_parent on transactions (parent_txn_id)
  where parent_txn_id is not null;

-- A split child must reference a parent owned by the same user, and a child
-- cannot itself be split (single-level splits only). Enforced by trigger —
-- an RLS with-check subquery cannot express "no grandchildren" cleanly.
create or replace function check_txn_split() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.parent_txn_id is not null then
    if not exists (
      select 1 from transactions p
      where p.id = new.parent_txn_id
        and p.user_id = new.user_id
        and p.parent_txn_id is null
    ) then
      raise exception 'invalid parent_txn_id';
    end if;
  end if;
  return new;
end $$;

create trigger trg_txn_split before insert or update on transactions
  for each row execute function check_txn_split();

-- ------------------------------------------------------- budgets: rollover
alter table budgets add column rollover boolean not null default false;
