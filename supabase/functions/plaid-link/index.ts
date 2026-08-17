// plaid-link: link a bank using Plaid Hosted Link (browser page — works from
// desktop, web, and Android without any native Plaid SDK). Requires a user JWT.
//
// POST { action: "create_hosted_link" }
//   -> { link_token, hosted_link_url }        client opens the URL in a browser
// POST { action: "complete", link_token, institution_name? }
//   -> { linked: true, accounts: n }          call after the user finishes Link
//   -> { linked: false }                      session not finished yet — retry
// POST { action: "unlink", item_id }          item_id = our plaid_items.id
//   -> { unlinked: true }                     removes the item at Plaid + our rows

import { adminClient, callerUserId, corsHeaders, json, plaid } from "../_shared/plaid.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  const userId = await callerUserId(req);
  if (!userId) return json({ error: "unauthorized" }, 401);

  const body = await req.json().catch(() => ({}));
  const db = adminClient();

  try {
    if (body.action === "create_hosted_link") {
      const data = await plaid<{ link_token: string; hosted_link_url: string }>(
        "/link/token/create", {
          user: { client_user_id: userId },
          client_name: "Monee",
          products: ["transactions"],
          country_codes: ["US"],
          language: "en",
          webhook: `${Deno.env.get("SUPABASE_URL")}/functions/v1/plaid-webhook`,
          hosted_link: {},
        },
      );
      // Remember who created this token so "complete" can verify ownership.
      const { error } = await db.from("link_tokens")
        .insert({ link_token: data.link_token, user_id: userId });
      if (error) throw new Error(error.message);
      return json({ link_token: data.link_token, hosted_link_url: data.hosted_link_url });
    }

    if (body.action === "complete") {
      if (typeof body.link_token !== "string") return json({ error: "link_token required" }, 400);
      // Only the user who created the token may complete it — otherwise a
      // signed-in user could claim someone else's freshly linked item.
      const { data: owner } = await db.from("link_tokens")
        .select("link_token")
        .eq("link_token", body.link_token)
        .eq("user_id", userId)
        .maybeSingle();
      if (!owner) return json({ error: "unknown link_token" }, 403);

      const info = await plaid<{
        link_sessions?: {
          results?: { item_add_results?: { public_token: string }[] };
        }[];
      }>("/link/token/get", { link_token: body.link_token });

      const publicToken =
        info.link_sessions?.[0]?.results?.item_add_results?.[0]?.public_token;
      if (!publicToken) return json({ linked: false });

      const ex = await plaid<{ access_token: string; item_id: string }>(
        "/item/public_token/exchange", { public_token: publicToken },
      );

      const { data: item, error: itemErr } = await db.from("plaid_items").upsert({
        user_id: userId,
        plaid_item_id: ex.item_id,
        access_token: ex.access_token,
        institution_name: body.institution_name ?? null,
      }, { onConflict: "plaid_item_id" }).select("id").single();
      if (itemErr) throw new Error(itemErr.message);

      const acc = await plaid<{ accounts: {
        account_id: string; name: string; subtype: string | null;
        balances: { current: number | null; iso_currency_code: string | null };
      }[] }>("/accounts/get", { access_token: ex.access_token });

      const rows = acc.accounts.map((a) => ({
        user_id: userId,
        plaid_item_id: item.id,
        plaid_account_id: a.account_id,
        name: a.name,
        type: a.subtype ?? "checking",
        currency: a.balances.iso_currency_code ?? "USD",
        current_balance: a.balances.current ?? 0,
        balance_updated_at: new Date().toISOString(),
      }));
      const { error: accErr } = await db.from("accounts")
        .upsert(rows, { onConflict: "plaid_account_id" });
      if (accErr) throw new Error(accErr.message);

      await db.from("link_tokens").delete().eq("link_token", body.link_token);
      return json({ linked: true, accounts: rows.length });
    }

    if (body.action === "unlink") {
      if (typeof body.item_id !== "string") return json({ error: "item_id required" }, 400);
      const { data: item } = await db.from("plaid_items")
        .select("id, access_token")
        .eq("id", body.item_id)
        .eq("user_id", userId)
        .maybeSingle();
      if (!item) return json({ error: "item not found" }, 404);

      try {
        await plaid("/item/remove", { access_token: item.access_token });
      } catch (_e) {
        // Item may already be gone at Plaid — still remove our rows.
      }
      const { error } = await db.from("plaid_items").delete().eq("id", item.id);
      if (error) throw new Error(error.message);
      return json({ unlinked: true });
    }

    return json({ error: "unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
