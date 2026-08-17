-- Monee initial schema. Every table is owned by user_id and protected by RLS.
-- Sign convention (matches Plaid): amount > 0 = money out, amount < 0 = money in.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- categories
create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade, -- null = system default
  name text not null,
  parent_id uuid references categories (id) on delete set null,
  icon text,
  created_at timestamptz not null default now()
);

-- --------------------------------------------------------------- plaid_items
create table plaid_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plaid_item_id text not null unique,
  access_token text not null,          -- clients cannot read this column (grants below)
  institution_name text,
  sync_cursor text,                    -- /transactions/sync cursor
  status text not null default 'active' check (status in ('active','error','disconnected')),
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------------ accounts
create table accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plaid_item_id uuid references plaid_items (id) on delete cascade, -- null = manual account
  plaid_account_id text unique,
  name text not null,
  type text not null default 'checking',
  currency text not null default 'USD',
  current_balance numeric(14,2) not null default 0,
  balance_updated_at timestamptz,
  created_at timestamptz not null default now()
);

-- -------------------------------------------------------------- transactions
create table transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references accounts (id) on delete cascade,
  plaid_transaction_id text unique,    -- null = manual entry
  amount numeric(14,2) not null,
  currency text not null default 'USD',
  date date not null,
  merchant_name text,
  description text,
  category_id uuid references categories (id) on delete set null,
  is_pending boolean not null default false,
  created_at timestamptz not null default now()
);

create index idx_txn_user_date on transactions (user_id, date desc);
create index idx_txn_account_date on transactions (account_id, date desc);

-- ------------------------------------------------------------------- budgets
create table budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  category_id uuid not null references categories (id) on delete cascade,
  month date not null,                 -- first day of month
  amount numeric(14,2) not null check (amount >= 0),
  created_at timestamptz not null default now(),
  unique (user_id, category_id, month)
);

-- ----------------------------------------------------------------- sync_logs
create table sync_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plaid_item_id uuid references plaid_items (id) on delete cascade,
  status text not null check (status in ('success','error')),
  txn_added int not null default 0,
  txn_modified int not null default 0,
  txn_removed int not null default 0,
  error_message text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------- RLS
alter table categories   enable row level security;
alter table plaid_items  enable row level security;
alter table accounts     enable row level security;
alter table transactions enable row level security;
alter table budgets      enable row level security;
alter table sync_logs    enable row level security;

-- categories: own rows full access; system rows (user_id is null) read-only.
create policy cat_select on categories for select
  using (user_id is null or auth.uid() = user_id);
create policy cat_write on categories for insert with check (auth.uid() = user_id);
create policy cat_update on categories for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy cat_delete on categories for delete using (auth.uid() = user_id);

-- plaid_items: user may see own rows (minus access_token via column grants)
-- and disconnect them; inserts/updates happen through Edge Functions (service role).
create policy pi_select on plaid_items for select using (auth.uid() = user_id);
create policy pi_delete on plaid_items for delete using (auth.uid() = user_id);

create policy acc_all on accounts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy txn_all on transactions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy bud_all on budgets for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy log_select on sync_logs for select using (auth.uid() = user_id);

-- Column-level privilege: hide access_token and sync_cursor from client roles.
revoke select on plaid_items from anon, authenticated;
grant select (id, user_id, plaid_item_id, institution_name, status, created_at)
  on plaid_items to authenticated;

-- Realtime on transactions so open clients refresh instantly.
alter publication supabase_realtime add table transactions;
