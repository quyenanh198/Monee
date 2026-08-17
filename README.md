# Monee

Personal finance app — tracks US bank accounts via Plaid plus manual accounts.
One Flutter codebase → desktop, Android APK (sideload), and web (Cloudflare Pages).
Runs entirely on free tiers: Supabase + Plaid Trial + Cloudflare Pages.

```
Flutter (Riverpod · go_router · fl_chart · supabase_flutter)
   └── Supabase: Auth · Postgres (RLS) · Realtime · Edge Functions
          └── Plaid: Hosted Link · /transactions/sync · webhook
```

Design spec: `docs/superpowers/specs/2026-08-17-monee-mvp-design.md`

## 1. Supabase setup

1. Create a project at supabase.com (free tier).
2. Apply migrations, in order, via SQL Editor or `supabase db push`:
   - `supabase/migrations/20260817000000_init.sql`
   - `supabase/migrations/20260817000001_seed_categories.sql`
3. Deploy Edge Functions:
   ```bash
   supabase functions deploy plaid-link
   supabase functions deploy plaid-sync
   supabase functions deploy plaid-webhook --no-verify-jwt
   ```
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

## 4. Builds

**Android APK (sideload, free):**
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
# app/build/app/outputs/flutter-apk/app-release.apk → copy to phone, install
```

**Desktop:**
```bash
flutter build windows   # or: macos / linux — same --dart-define flags
```

**Web → Cloudflare Pages:**
```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
npx wrangler pages deploy app/build/web --project-name=monee
```
(Or connect the repo in the Cloudflare dashboard with build command
`cd app && flutter build web --release --dart-define=...` and output dir `app/build/web`.)

## 5. Linking a bank

App → Dashboard → biểu tượng ngân hàng → **Liên kết ngân hàng (Plaid)**.
A Plaid Hosted Link page opens in the browser (works on desktop, Android, and web —
no native SDK). Finish the flow there, come back, press **Đã xong**.

## Conventions

- `transactions.amount` follows Plaid: **positive = money out, negative = money in**.
- Plaid access tokens live only in `plaid_items.access_token`; column-level grants
  prevent clients from ever reading them. All Plaid calls happen in Edge Functions.

## Post-MVP hardening (known, intentional deferrals)

- Verify Plaid webhook JWS signatures in `plaid-webhook` (currently the payload is
  untrusted-by-design: only `item_id` is used, to re-sync an item we already own).
- Periodic DB export (free tier has no automatic backups).
- Multi-currency conversion, recurring detection, shared accounts.
