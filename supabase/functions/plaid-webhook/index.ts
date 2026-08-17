// plaid-webhook: Plaid notifies here when an item has new data.
// Security model: nothing in the payload is trusted except item_id, which is only
// used to look up an item we already store and re-run our own authenticated sync.
// (Full Plaid JWS webhook verification is a post-MVP hardening step.)

import { adminClient, json, syncItem } from "../_shared/plaid.ts";

Deno.serve(async (req) => {
  const body = await req.json().catch(() => null);
  const itemId = body?.item_id;
  if (typeof itemId !== "string") return json({ ok: true }); // ignore malformed

  const db = adminClient();
  const { data: item } = await db.from("plaid_items")
    .select("id, user_id, access_token, sync_cursor")
    .eq("plaid_item_id", itemId)
    .eq("status", "active")
    .maybeSingle();
  if (!item) return json({ ok: true }); // unknown item — ack, do nothing

  try {
    await syncItem(db, item);
  } catch (_e) {
    // already logged to sync_logs; still ack so Plaid does not retry-storm
  }
  return json({ ok: true });
});
