// plaid-sync: pull new/changed transactions for Plaid items.
//
// Two callers:
//   1. The app (user JWT) — syncs that user's items on demand.
//   2. Cron (header x-cron-secret == CRON_SECRET) — syncs every active item daily.
//      Schedule with pg_cron + pg_net or an external scheduler (see README).

import { adminClient, callerUserId, corsHeaders, json, safeEqual, syncItem } from "../_shared/plaid.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });

  const db = adminClient();
  const cronSecret = Deno.env.get("CRON_SECRET");
  const cronHeader = req.headers.get("x-cron-secret");
  const isCron = !!cronSecret && !!cronHeader && safeEqual(cronHeader, cronSecret);
  const userId = isCron ? null : await callerUserId(req);
  if (!isCron && !userId) return json({ error: "unauthorized" }, 401);

  let q = db.from("plaid_items")
    .select("id, user_id, access_token, sync_cursor")
    .eq("status", "active");
  if (userId) q = q.eq("user_id", userId);
  const { data: items, error } = await q;
  if (error) return json({ error: error.message }, 500);

  const results: Record<string, unknown>[] = [];
  for (const item of items ?? []) {
    try {
      results.push({ item: item.id, ...(await syncItem(db, item)) });
    } catch (e) {
      results.push({ item: item.id, error: String(e) });
    }
  }
  return json({ synced: results.length, results });
});
