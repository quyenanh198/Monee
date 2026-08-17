# Monee — MVP Design (approved 2026-08-17)

Personal finance app for personal use. Tracks 2 US bank accounts via Plaid, plus manual
accounts/transactions. Runs at $0: Flutter clients (desktop, Android APK sideload, web on
Cloudflare Pages), Supabase free tier (DB + Auth + Edge Functions), Plaid Trial plan.

## Goals

- One codebase (Flutter) → desktop, Android APK, web.
- Bank data synced automatically from Plaid; manual entry also supported.
- Multi-user-ready schema (RLS on every table) even though there is one user today.
- Plaid access tokens never reach the client.

## Non-goals (MVP)

Multi-currency conversion, shared/family accounts, recurring-transaction detection,
investments/crypto, iOS distribution. Schema leaves room for all of these.

## Features

| Module | Contents |
|---|---|
| Auth | Supabase email/password |
| Dashboard | Total balance, monthly spend by category (donut), 10 recent transactions |
| Accounts | Plaid-linked + manual accounts, balances, sync status |
| Transactions | Paginated list, filter by account/category/date, search, manual CRUD, categorize |
| Categories | Seeded defaults + user-defined |
| Budgets | Monthly per-category budget, progress bar, over-budget warning |
| Reports | 6-month income vs expense (bars), category breakdown (donut) |
| Plaid sync | Link flow, daily sync (transactions/sync cursor), webhook-triggered sync |
| Settings | Dark/light theme, CSV export, sign out |

## Architecture

```
Flutter app (Riverpod + go_router + fl_chart + supabase_flutter)
   │  anon key, RLS-scoped queries, Realtime stream on transactions
   ▼
Supabase
   ├─ Postgres: plaid_items, accounts, transactions, categories, budgets, sync_logs
   │   RLS: every row owned by user_id; access_token column not readable by clients
   └─ Edge Functions (Deno, service role):
       ├─ plaid-link     create_link_token / exchange public_token
       ├─ plaid-sync     /transactions/sync with stored cursor; cron daily
       └─ plaid-webhook  Plaid calls it; triggers sync for the item
```

Sign convention: `transactions.amount` follows Plaid — positive = money out (expense),
negative = money in (income).

## Data model

See `supabase/migrations/`. Key decisions:

- `user_id` + RLS on every table → multi-user without schema change.
- `plaid_transaction_id` nullable → manual entries and future CSV import.
- `currency` per row → future multi-currency without migration.
- `plaid_items` separate from `accounts` → future non-Plaid sources.
- Column-level grant hides `plaid_items.access_token` from clients.
- Indexes `(user_id, date desc)` and `(account_id, date desc)` on transactions.

## Security

- Client uses anon key only; every query passes RLS (`auth.uid() = user_id`).
- Edge Functions hold `PLAID_CLIENT_ID` / `PLAID_SECRET` / service-role key as secrets.
- `plaid-sync` accepts either a valid user JWT (manual refresh) or `x-cron-secret`.
- `plaid-webhook` trusts nothing from the payload except `item_id`; it only triggers a
  re-sync of an item that already exists. (Full Plaid JWS webhook verification is a
  post-MVP hardening step, documented in README.)

## UI design system (ui-ux-pro-max)

- Style: Data-Dense Dashboard. Dark default `#0F172A`, light supported.
- Colors: primary `#1E40AF`, secondary `#3B82F6`, accent/positive `#059669`,
  destructive `#DC2626`, border `rgba(255,255,255,0.08)`.
- Type: Fira Sans (UI) + Fira Code (numbers), base 16, line-height 1.5.
- Navigation: bottom nav (narrow) / navigation rail (wide) — Dashboard, Transactions,
  Budgets, Reports, Settings. Accounts reachable from Dashboard.
- Rules: contrast ≥ 4.5:1, touch targets ≥ 44px, transitions 150–300ms, Lucide icons,
  no emoji-as-icon.

## Verification criteria

- `flutter analyze` clean; `flutter test` passes (budget math, model parsing, CSV export).
- Migrations apply cleanly on a fresh Supabase project.
- `deno check` passes on Edge Functions.
- `flutter build web` succeeds; output deploys to Cloudflare Pages.

Sandbox note: Flutter/Deno SDKs are unavailable in the authoring environment; the four
checks above are run by the owner locally. Test files are committed alongside the code.
