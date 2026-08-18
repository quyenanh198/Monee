-- Sync-lifecycle and data-consistency fixes (2026-08-19 code review).
--
-- 1. plaid_items gains status 'login_required' (ITEM_LOGIN_REQUIRED needs a
--    re-auth flow, not a blind retry like transient errors).
-- 2. link_tokens.item_id marks a token created in Link *update mode* for an
--    existing item; completing it re-activates the item.
-- 3. transactions gets REPLICA IDENTITY FULL so realtime DELETE events carry
--    the full row and pass the user_id filter of the dashboard stream.
-- 4. split_transaction(): atomic replace-children RPC that also enforces the
--    children-sum-equals-parent invariant server-side (two devices splitting
--    concurrently can no longer double the children).

-- ------------------------------------------------------------- plaid_items
alter table plaid_items drop constraint plaid_items_status_check;
alter table plaid_items add constraint plaid_items_status_check
  check (status in ('active','error','login_required','disconnected'));

-- ------------------------------------------------------------- link_tokens
alter table link_tokens add column item_id uuid
  references plaid_items (id) on delete cascade;

-- ------------------------------------------------------------ transactions
alter table transactions replica identity full;

-- -------------------------------------------------------- split_transaction
-- parts: jsonb array of {"amount": number, "category_id": uuid|null}.
-- Runs with invoker rights: RLS policies still gate every row it touches.
create or replace function split_transaction(p_parent uuid, p_parts jsonb)
returns void
language plpgsql
set search_path = public as $$
declare
  parent_row transactions%rowtype;
  parts_sum numeric;
begin
  -- FOR UPDATE serializes concurrent splits of the same parent: the second
  -- caller waits, then its delete removes the first caller's children
  -- (clean last-writer-wins) instead of doubling them.
  select * into parent_row from transactions
    where id = p_parent and parent_txn_id is null
    for update;
  if not found then
    raise exception 'parent not found';
  end if;

  if jsonb_typeof(p_parts) <> 'array' or jsonb_array_length(p_parts) < 2 then
    raise exception 'need at least 2 parts';
  end if;

  select coalesce(sum((p->>'amount')::numeric), 0) into parts_sum
    from jsonb_array_elements(p_parts) p;
  if abs(parts_sum - parent_row.amount) > 0.01 then
    raise exception 'parts must sum to the parent amount';
  end if;

  delete from transactions where parent_txn_id = p_parent;

  insert into transactions
    (user_id, account_id, amount, currency, date, description,
     category_id, parent_txn_id)
  select
    parent_row.user_id,
    parent_row.account_id,
    (p->>'amount')::numeric,
    parent_row.currency,
    parent_row.date,
    coalesce(parent_row.merchant_name, parent_row.description) || ' (tách)',
    nullif(p->>'category_id','')::uuid,
    parent_row.id
  from jsonb_array_elements(p_parts) p;
end $$;

grant execute on function split_transaction(uuid, jsonb) to authenticated;
