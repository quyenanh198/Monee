// fx-rate: USD→VND reference rate for display conversion.
// Free, key-less upstream (open.er-api.com, updated daily). Requires a user
// JWT (deploy with default verify_jwt) — this endpoint costs nothing but
// there is no reason to serve it anonymously.

import { corsHeaders, json } from "../_shared/plaid.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  try {
    const res = await fetch("https://open.er-api.com/v6/latest/USD");
    const data = await res.json().catch(() => null);
    const rate = data?.rates?.VND;
    if (typeof rate !== "number" || rate <= 0) {
      return json({ error: "rate unavailable" }, 502);
    }
    return json({
      base: "USD",
      quote: "VND",
      rate,
      updated: data?.time_last_update_utc ?? null,
    });
  } catch (e) {
    return json({ error: String(e) }, 502);
  }
});
