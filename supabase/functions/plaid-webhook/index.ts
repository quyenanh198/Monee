// plaid-webhook: Plaid notifies here when an item has new data.
// Security model: nothing in the payload is trusted except item_id, which is only
// used to look up an item we already store and re-run our own authenticated sync.
// (Full Plaid JWS webhook verification is a post-MVP hardening step.)
// A per-item cooldown bounds how often a blind POST can force a Plaid sync.

import { adminClient, json, syncItem } from "../_shared/plaid.ts";

const COOLDOWN_MS = 45_000;

Deno.serve(async (req) => {
  const body = await req.json().catch(() => null);
  const itemId = body?.item_id;
  if (typeof itemId !== "string") return json({ ok: true }); // ignore malformed

  const db = adminClient();
  const { data: item } = await db.from("plaid_items")
    .select("id, user_id, access_token, sync_cursor")
    .eq("plaid_item_id", itemId)
    .in("status", ["active", "error"]) // retry errored items; skip login_required
    .maybeSingle();
  if (!item) return json({ ok: true }); // unknown item — ack, do nothing

  // Cooldown: if this item synced moments ago, ack without re-syncing. Also
  // reduces cursor races between webhook- and user-triggered syncs.
  const { data: last } = await db.from("sync_logs")
    .select("created_at")
    .eq("plaid_item_id", item.id)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (last && Date.now() - new Date(last.created_at).getTime() < COOLDOWN_MS) {
    return json({ ok: true, throttled: true });
  }

  try {
    await syncItem(db, item);
  } catch (_e) {
    // already logged to sync_logs; still ack so Plaid does not retry-storm
  }
  return json({ ok: true });
});
