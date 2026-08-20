# Monee

![CI](https://github.com/quyenanh198/Monee/actions/workflows/ci.yml/badge.svg?branch=main)

Personal finance app — tracks US bank accounts via Plaid plus manual accounts.
One Flutter codebase → desktop, Android APK (sideload), and web (Cloudflare Pages).
Runs entirely on free tiers: Supabase + Plaid Trial + Cloudflare Pages.

**Live web app:** https://monee-3ee.pages.dev ·
**Windows / Android downloads:** [GitHub Releases](https://github.com/quyenanh198/Monee/releases)

```
Flutter (Riverpod · go_router · fl_chart · supabase_flutter)
   └── Supabase: Auth · Postgres (RLS) · Realtime · Edge Functions
          └── Plaid: Hosted Link · /transactions/sync · webhook
```

Features: Plaid sync + manual accounts · realtime cross-device updates ·
budgets with rollover · auto-categorization rules · recurring-charge
detection, upcoming bills & 30-day cash-flow forecast · net-worth history ·
savings goals · split transactions, notes & tags · reports · CSV
import/export · VND display conversion · dark/light theme.

Design spec: `docs/superpowers/specs/2026-08-17-monee-mvp-design.md` ·
Flow diagrams: `docs/flow.html`

## 1. Supabase setup

1. Create a project at supabase.com (free tier).
2. Apply every file in `supabase/migrations/` in filename order, via SQL
   Editor or `supabase db push` (init → seed_categories → security_hardening
   → features → sync_fixes → realtime_tables).
3. Deploy Edge Functions:
   ```bash
   supabase functions deploy plaid-link
   supabase functions deploy plaid-sync --no-verify-jwt
   supabase functions deploy plaid-webhook --no-verify-jwt
   supabase functions deploy fx-rate
   ```
   `plaid-sync` needs `--no-verify-jwt` because the pg_cron call carries no JWT;
   the function enforces auth itself (user JWT or `x-cron-secret`). Same for
   `plaid-webhook` (called by Plaid). `fx-rate` serves the USD→VND display
   rate (free key-less upstream: open.er-api.com).
4. Set function secrets:
   ```bash
   supabase secrets set \
     PLAID_CLIENT_ID=... \
     PLAID_SECRET=... \
     PLAID_ENV=production \
     CRON_SECRET=$(openssl rand -hex 24)
   ```
5. Daily sync — schedule with pg_cron + pg_net (SQL Editor):
   ```sql
   select cron.schedule('monee-daily-sync', '0 12 * * *', $$
     select net.http_post(
       url    := 'https://<project-ref>.supabase.co/functions/v1/plaid-sync',
       headers:= '{"x-cron-secret": "<CRON_SECRET>"}'::jsonb
     );
   $$);
   ```
   This daily call also keeps the free-tier project from pausing (7-day inactivity rule).

## 2. Plaid setup

1. Create a Plaid account, apply for the **Trial plan** (free, 10 Items — plenty for
   2 banks): dashboard.plaid.com/trial-plan.
2. Copy `client_id` + `secret` into the function secrets above.
3. Allow Hosted Link redirect defaults (no extra config needed for hosted flow).

## 3. Flutter app

Prereqs: Flutter SDK ≥ 3.24. Platform folders are not committed — generate once:

```bash
cd app
flutter create . --platforms=web,windows,macos,linux,android
flutter pub get
```

Run (any platform):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Checks:

```bash
flutter analyze
flutter test
```

## 4. Builds & releases

**Release packages (Windows + Android) — via GitHub Actions:** push a tag
and `.github/workflows/release.yml` builds the Android APK (ubuntu runner)
and the Windows zip (windows runner), then attaches both to a GitHub
Release:

```bash
git tag v0.1.0 && git push origin v0.1.0
# → https://github.com/quyenanh198/Monee/releases
```

The workflow bakes in the production `SUPABASE_URL`/`SUPABASE_ANON_KEY`
(the publishable key is public by design — RLS guards the data). The APK is
debug-signed — fine for sideloading; add a keystore only if you ever ship
to Play Store.

**Android APK (local build):**
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
# app/build/app/outputs/flutter-apk/app-release.apk → copy to phone, install
```

**Desktop (local build, needs that OS):**
```bash
flutter build windows   # or: macos / linux — same --dart-define flags
```

**Web → Cloudflare Pages:**
```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
npx wrangler pages deploy app/build/web --project-name=monee --branch=main
```
`--branch=main` matters: wrangler otherwise infers the git branch and the
deploy lands on a preview URL instead of production.

## 5. Linking a bank

App → Dashboard → biểu tượng ngân hàng → **Liên kết ngân hàng (Plaid)**.
A Plaid Hosted Link page opens in the browser (works on desktop, Android, and web —
no native SDK). Finish the flow there, come back, press **Đã xong**.

## Conventions

- `transactions.amount` follows Plaid: **positive = money out, negative = money in**.
- Plaid access tokens live only in `plaid_items.access_token`; column-level grants
  prevent clients from ever reading them. All Plaid calls happen in Edge Functions.
- Link tokens are recorded per user (`link_tokens`, service-role only) so the
  `complete` step only accepts tokens created by the same signed-in user.
- RLS validates client-written foreign keys: transactions must reference your own
  account, accounts your own Plaid item, budgets a system or own category.
- Deleting the last account of a Plaid item unlinks the item (Plaid `/item/remove`
  + row cleanup) so no orphan item keeps syncing.

## Post-MVP hardening (known, intentional deferrals)

- Verify Plaid webhook JWS signatures in `plaid-webhook` (currently the payload is
  untrusted-by-design: only `item_id` is used, to re-sync an item we already own).
- Periodic DB export (free tier has no automatic backups).
- Full multi-currency accounting (display-only VND conversion is built in),
  shared accounts, push notifications (needs a Firebase project), AI Q&A
  (needs a paid LLM API key).
