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
  let q = db.from("accounts").select("user_id, current_balance");
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
 * Run /transactions/sync for one plaid_items row until has_more is false.
 * Upserts transactions (applying the user's categorization rules to new
 * ones), applies removals, updates balances + cursor, writes a sync_log.
 */
export async function syncItem(
  db: SupabaseClient,
  item: { id: string; user_id: string; access_token: string; sync_cursor: string | null },
): Promise<{ added: number; modified: number; removed: number }> {
  let cursor = item.sync_cursor ?? undefined;
  let added = 0, modified = 0, removed = 0;

  // account map: plaid_account_id -> our uuid
  const { data: accounts } = await db
    .from("accounts").select("id, plaid_account_id").eq("plaid_item_id", item.id);
  const accMap = new Map((accounts ?? []).map((a) => [a.plaid_account_id as string, a.id as string]));

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

      // Batches must have uniform columns: added rows with a rule match carry
      // category_id; everything else omits it so existing categories survive.
      const withCategory: Record<string, unknown>[] = [];
      const withoutCategory: Record<string, unknown>[] = [];
      for (const t of page.added) {
        if (!accMap.has(t.account_id)) continue;
        const cat = matchRule(rules, t.merchant_name, t.name);
        if (cat) withCategory.push({ ...toRow(t), category_id: cat });
        else withoutCategory.push(toRow(t));
      }
      for (const t of page.modified) {
        if (accMap.has(t.account_id)) withoutCategory.push(toRow(t));
      }
      for (const batch of [withCategory, withoutCategory]) {
        if (!batch.length) continue;
        const { error } = await db.from("transactions")
          .upsert(batch, { onConflict: "plaid_transaction_id" });
        if (error) throw new Error(error.message);
      }
      if (page.removed.length) {
        const { error } = await db.from("transactions").delete()
          .in("plaid_transaction_id", page.removed.map((r) => r.transaction_id));
        if (error) throw new Error(error.message);
      }

      added += page.added.length;
      modified += page.modified.length;
      removed += page.removed.length;
      cursor = page.next_cursor;
      hasMore = page.has_more;
    }

    // Refresh balances.
    const bal = await plaid<{ accounts: { account_id: string; balances: { current: number | null } }[] }>(
      "/accounts/balance/get", { access_token: item.access_token },
    );
    for (const a of bal.accounts) {
      const id = accMap.get(a.account_id);
      if (id && a.balances.current !== null) {
        await db.from("accounts").update({
          current_balance: a.balances.current,
          balance_updated_at: new Date().toISOString(),
        }).eq("id", id);
      }
    }

    await db.from("plaid_items").update({ sync_cursor: cursor, status: "active" }).eq("id", item.id);
    await db.from("sync_logs").insert({
      user_id: item.user_id, plaid_item_id: item.id, status: "success",
      txn_added: added, txn_modified: modified, txn_removed: removed,
    });
    return { added, modified, removed };
  } catch (e) {
    await db.from("plaid_items").update({ status: "error" }).eq("id", item.id);
    await db.from("sync_logs").insert({
      user_id: item.user_id, plaid_item_id: item.id, status: "error",
      error_message: String(e),
    });
    throw e;
  }
}
