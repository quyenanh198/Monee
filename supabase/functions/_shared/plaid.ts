// Shared helpers for Monee Edge Functions.
// Plaid is called with plain fetch — no SDK dependency.

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export const PLAID_ENV = Deno.env.get("PLAID_ENV") ?? "production";
const PLAID_BASE = `https://${PLAID_ENV}.plaid.com`;

export function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Content-Type": "application/json",
  };
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders() });
}

/** Call a Plaid endpoint. Throws on non-2xx with Plaid's error body. */
export async function plaid<T>(path: string, body: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${PLAID_BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: Deno.env.get("PLAID_CLIENT_ID"),
      secret: Deno.env.get("PLAID_SECRET"),
      ...body,
    }),
  });
  // Errors from proxies/outages may be non-JSON — keep the message useful.
  const text = await res.text();
  let data: Record<string, unknown> | null = null;
  try {
    data = JSON.parse(text);
  } catch {
    data = null;
  }
  if (!res.ok) {
    throw new Error(
      `Plaid ${path}: ${data?.error_code ?? res.status} ${data?.error_message ?? text.slice(0, 200)}`,
    );
  }
  if (data === null) throw new Error(`Plaid ${path}: non-JSON response (HTTP ${res.status})`);
  return data as T;
}

/** Constant-time string comparison for shared secrets. */
export function safeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

/** Service-role client — bypasses RLS. Server-side only. */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

/** Resolve the calling user from the request JWT. Returns null if invalid/absent. */
export async function callerUserId(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization");
  if (!auth) return null;
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data, error } = await client.auth.getUser();
  return error ? null : data.user.id;
}

export interface PlaidTxn {
  transaction_id: string;
  account_id: string;
  amount: number;
  iso_currency_code: string | null;
  date: string;
  merchant_name: string | null;
  name: string;
  pending: boolean;
  /** On a posted txn: the id of the pending txn it replaces. */
  pending_transaction_id: string | null;
}

interface Rule {
  pattern: string;
  match_field: "merchant" | "description" | "any";
  category_id: string;
}

/** First rule whose pattern is contained (case-insensitive) in the txn's text. */
export function matchRule(
  rules: Rule[],
  merchant: string | null,
  description: string | null,
): string | null {
  const m = (merchant ?? "").toLowerCase();
  const d = (description ?? "").toLowerCase();
  for (const r of rules) {
    const p = r.pattern.toLowerCase();
    const hit = r.match_field === "merchant"
      ? m.includes(p)
      : r.match_field === "description"
      ? d.includes(p)
      : m.includes(p) || d.includes(p);
    if (hit) return r.category_id;
  }
  return null;
}

/**
 * Daily net-worth snapshot: one row per user per day, total across all
 * accounts. Pass userId to snapshot one user, omit for everyone (cron).
 */
export async function snapshotBalances(db: SupabaseClient, userId?: string): Promise<void> {
  // USD only: summing mixed currencies produces a meaningless number, and the
  // ledger currency of the app is USD. Non-USD accounts are excluded from net
  // worth until real multi-currency accounting lands (deliberate deferral).
  let q = db.from("accounts").select("user_id, current_balance")
    .eq("currency", "USD");
  if (userId) q = q.eq("user_id", userId);
  const { data } = await q;
  if (!data?.length) return;
  const totals = new Map<string, number>();
  for (const a of data) {
    totals.set(a.user_id, (totals.get(a.user_id) ?? 0) + Number(a.current_balance));
  }
  const today = new Date().toISOString().slice(0, 10);
  const rows = [...totals].map(([uid, total]) => ({
    user_id: uid,
    date: today,
    total: Math.round(total * 100) / 100,
  }));
  await db.from("balance_snapshots").upsert(rows, { onConflict: "user_id,date" });
}

/**
 * When a synced parent's amount changed but its split children still sum to
 * the old amount, the children are stale: delete them so the parent counts
 * again as an unsplit txn (the user can re-split with correct numbers).
 */
async function repairSplits(db: SupabaseClient, plaidTxnIds: string[]): Promise<void> {
  if (!plaidTxnIds.length) return;
  const { data: parents } = await db.from("transactions")
    .select("id, amount").in("plaid_transaction_id", plaidTxnIds);
  if (!parents?.length) return;
  const { data: children } = await db.from("transactions")
    .select("parent_txn_id, amount").in("parent_txn_id", parents.map((p) => p.id));
  if (!children?.length) return;
  const sums = new Map<string, number>();
  for (const c of children) {
    sums.set(c.parent_txn_id, (sums.get(c.parent_txn_id) ?? 0) + Number(c.amount));
  }
  const broken = parents
    .filter((p) => sums.has(p.id) && Math.abs(Number(p.amount) - sums.get(p.id)!) > 0.01)
    .map((p) => p.id);
  if (broken.length) {
    await db.from("transactions").delete().in("parent_txn_id", broken);
  }
}

/**
 * Run /transactions/sync for one plaid_items row until has_more is false.
 * - pending→posted transitions migrate the existing row in place, so the
 *   user's category/note/tags/splits survive (pending_transaction_id link);
 * - accounts newly added at the bank are created on the fly — a transaction
 *   for a still-unknown account fails the sync loudly BEFORE the cursor is
 *   saved, so nothing is ever silently dropped behind the cursor;
 * - the cursor is saved with compare-and-swap: if a concurrent sync already
 *   advanced it, this run's (idempotent) writes stand but the cursor is not
 *   regressed;
 * - ITEM_LOGIN_REQUIRED maps to status 'login_required' (needs re-auth flow),
 *   other failures to 'error' (retried by the next cron/manual sync).
 */
export async function syncItem(
  db: SupabaseClient,
  item: { id: string; user_id: string; access_token: string; sync_cursor: string | null },
): Promise<{ added: number; modified: number; removed: number }> {
  const originalCursor = item.sync_cursor;
  let cursor = item.sync_cursor ?? undefined;
  let added = 0, modified = 0, removed = 0;

  // account map: plaid_account_id -> our uuid
  let accMap = new Map<string, string>();
  const loadAccounts = async () => {
    const { data } = await db
      .from("accounts").select("id, plaid_account_id").eq("plaid_item_id", item.id);
    accMap = new Map((data ?? []).map((a) => [a.plaid_account_id as string, a.id as string]));
  };
  await loadAccounts();

  // The bank can add accounts to an existing item; create them before use.
  const ensureAccounts = async (accountIds: Iterable<string>) => {
    if (![...accountIds].some((id) => !accMap.has(id))) return;
    const acc = await plaid<{ accounts: {
      account_id: string; name: string; subtype: string | null;
      balances: { current: number | null; iso_currency_code: string | null };
    }[] }>("/accounts/get", { access_token: item.access_token });
    const rows = acc.accounts
      .filter((a) => !accMap.has(a.account_id))
      .map((a) => ({
        user_id: item.user_id,
        plaid_item_id: item.id,
        plaid_account_id: a.account_id,
        name: a.name,
        type: a.subtype ?? "checking",
        currency: a.balances.iso_currency_code ?? "USD",
        current_balance: a.balances.current ?? 0,
        balance_updated_at: new Date().toISOString(),
      }));
    if (rows.length) {
      const { error } = await db.from("accounts")
        .upsert(rows, { onConflict: "plaid_account_id" });
      if (error) throw new Error(error.message);
    }
    await loadAccounts();
  };

  // Categorization rules — applied to newly added transactions only, so a
  // user's manual category on an existing row is never overwritten.
  const { data: ruleRows } = await db
    .from("rules").select("pattern, match_field, category_id")
    .eq("user_id", item.user_id).order("created_at");
  const rules = (ruleRows ?? []) as { pattern: string; match_field: "merchant" | "description" | "any"; category_id: string }[];

  try {
    for (let hasMore = true; hasMore;) {
      const page = await plaid<{
        added: PlaidTxn[]; modified: PlaidTxn[];
        removed: { transaction_id: string }[];
        next_cursor: string; has_more: boolean;
      }>("/transactions/sync", { access_token: item.access_token, cursor, count: 500 });

      const all = [...page.added, ...page.modified];
      await ensureAccounts(all.map((t) => t.account_id));
      for (const t of all) {
        if (!accMap.has(t.account_id)) {
          // Fail BEFORE the cursor advances — a skipped txn would be lost forever.
          throw new Error(`unknown Plaid account ${t.account_id}`);
        }
      }

      const toRow = (t: PlaidTxn) => ({
        user_id: item.user_id,
        account_id: accMap.get(t.account_id),
        plaid_transaction_id: t.transaction_id,
        amount: t.amount,
        currency: t.iso_currency_code ?? "USD",
        date: t.date,
        merchant_name: t.merchant_name,
        description: t.name,
        is_pending: t.pending,
      });

      // pending→posted: update the pending row in place under the new txn id,
      // preserving category/note/tags and split children.
      const amountChanged: string[] = []; // new plaid ids whose amount may differ
      const stillNew: PlaidTxn[] = [];
      for (const t of page.added) {
        if (t.pending_transaction_id) {
          const { data: migrated, error } = await db.from("transactions")
            .update(toRow(t))
            .eq("plaid_transaction_id", t.pending_transaction_id)
            .select("id");
          if (error) throw new Error(error.message);
          if (migrated?.length) {
            amountChanged.push(t.transaction_id);
            continue;
          }
        }
        stillNew.push(t);
      }

      // Batches must have uniform columns: added rows with a rule match carry
      // category_id; everything else omits it so existing categories survive.
      const withCategory: Record<string, unknown>[] = [];
      const withoutCategory: Record<string, unknown>[] = [];
      for (const t of stillNew) {
        const cat = matchRule(rules, t.merchant_name, t.name);
        if (cat) withCategory.push({ ...toRow(t), category_id: cat });
        else withoutCategory.push(toRow(t));
      }
      for (const t of page.modified) {
        withoutCategory.push(toRow(t));
        amountChanged.push(t.transaction_id);
      }
      for (const batch of [withCategory, withoutCategory]) {
        if (!batch.length) continue;
        const { error } = await db.from("transactions")
          .upsert(batch, { onConflict: "plaid_transaction_id" });
        if (error) throw new Error(error.message);
      }

      // Deletes: migrated pending ids no longer match (their row now carries
      // the posted id), so this only removes genuinely removed transactions.
      if (page.removed.length) {
        const { error } = await db.from("transactions").delete()
          .in("plaid_transaction_id", page.removed.map((r) => r.transaction_id));
        if (error) throw new Error(error.message);
      }

      await repairSplits(db, amountChanged);

      added += page.added.length;
      modified += page.modified.length;
      removed += page.removed.length;
      cursor = page.next_cursor;
      hasMore = page.has_more;
    }

    // Refresh balances (concurrently — independent rows).
    const bal = await plaid<{ accounts: { account_id: string; balances: { current: number | null } }[] }>(
      "/accounts/balance/get", { access_token: item.access_token },
    );
    await Promise.all(bal.accounts
      .filter((a) => accMap.has(a.account_id) && a.balances.current !== null)
      .map((a) => db.from("accounts").update({
        current_balance: a.balances.current,
        balance_updated_at: new Date().toISOString(),
      }).eq("id", accMap.get(a.account_id)!)));

    // Compare-and-swap the cursor: only claim it if no concurrent sync
    // advanced it since we read it. Our row writes are idempotent upserts,
    // so losing the race is harmless — just don't regress the cursor.
    let claim = db.from("plaid_items")
      .update({ sync_cursor: cursor, status: "active" })
      .eq("id", item.id);
    claim = originalCursor === null
      ? claim.is("sync_cursor", null)
      : claim.eq("sync_cursor", originalCursor);
    const { data: claimed, error: claimErr } = await claim.select("id");
    if (claimErr) throw new Error(claimErr.message);
    const lostRace = !claimed?.length;
    if (lostRace) {
      // Still clear a stale error state; leave the newer cursor alone.
      await db.from("plaid_items").update({ status: "active" }).eq("id", item.id);
    }

    await db.from("sync_logs").insert({
      user_id: item.user_id, plaid_item_id: item.id, status: "success",
      txn_added: added, txn_modified: modified, txn_removed: removed,
      error_message: lostRace ? "concurrent sync won the cursor race" : null,
    });
    return { added, modified, removed };
  } catch (e) {
    const msg = String(e);
    if (msg.includes("TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION")) {
      // Concurrent sync mutated the stream mid-pagination. Benign: nothing
      // was lost (cursor unsaved, writes idempotent) — the next sync retries.
      await db.from("sync_logs").insert({
        user_id: item.user_id, plaid_item_id: item.id, status: "error",
        error_message: "retryable: " + msg,
      });
      return { added, modified, removed };
    }
    const status = msg.includes("ITEM_LOGIN_REQUIRED") ? "login_required" : "error";
    await db.from("plaid_items").update({ status }).eq("id", item.id);
    await db.from("sync_logs").insert({
      user_id: item.user_id, plaid_item_id: item.id, status: "error",
      error_message: msg,
    });
    throw e;
  }
}
