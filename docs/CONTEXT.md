# Monee — Session Context & Handoff

> File này là nguồn context duy nhất giữa các phiên làm việc (Claude chat / Claude Code).
> Cập nhật mục **Trạng thái** và **Nhật ký phiên** sau mỗi phiên. Nên commit vào repo tại `docs/CONTEXT.md`.

---

## 1. Dự án

App tài chính cá nhân, dùng riêng, tổng chi phí vận hành **$0**.
Theo dõi 2 tài khoản ngân hàng Mỹ qua Plaid + tài khoản/giao dịch nhập tay.

| Hạng mục | Quyết định |
|---|---|
| Tên | **Monee** |
| Repo | https://github.com/quyenanh198/Monee |
| Client | **Flutter** — 1 codebase: desktop + Android APK (sideload) + web |
| Web host | **Cloudflare Pages** |
| iOS | Bỏ qua ($99/năm) — thay bằng PWA trên Safari |
| Backend | **Supabase** free tier: Auth + Postgres (RLS) + Realtime + Edge Functions |
| Bank sync | **Plaid Trial** (free, giới hạn 10 Items) — dùng **Hosted Link** |

## 2. Cấu trúc repo

```
Monee/
├─ docs/superpowers/specs/2026-08-17-monee-mvp-design.md   # design đã duyệt
├─ docs/flow.html                         # 4 sơ đồ flow: điều hướng, Plaid link, sync, bảo mật
├─ supabase/
│  ├─ migrations/
│  │  ├─ 20260817000000_init.sql          # schema + RLS + index + grants
│  │  ├─ 20260817000001_seed_categories.sql  # 12 category mặc định
│  │  ├─ 20260817000002_security_hardening.sql  # link_tokens + siết RLS FK
│  │  └─ 20260818000000_features.sql       # rules, snapshots, goals, split/note/tags, rollover
│  └─ functions/
│     ├─ _shared/plaid.ts                 # helper: gọi Plaid, syncItem()
│     ├─ plaid-link/index.ts              # Hosted Link: create + complete
│     ├─ plaid-sync/index.ts              # /transactions/sync (JWT hoặc cron)
│     └─ plaid-webhook/index.ts           # nhận webhook, trigger re-sync
├─ app/                                   # Flutter
│  ├─ lib/core/        # env, theme, router, formatters
│  ├─ lib/models/      # Account, Txn, Category, Budget
│  ├─ lib/data/        # repositories.dart (Riverpod providers + PlaidService)
│  ├─ lib/features/    # auth, shell, dashboard, accounts, transactions,
│  │                   # budgets (budget_logic.dart thuần — có test),
│  │                   # recurring (recurring_logic.dart thuần — có test),
│  │                   # goals, rules, reports,
│  │                   # settings (csv_export.dart thuần — có test)
│  ├─ lib/widgets/     # common.dart
│  └─ test/logic_test.dart
└─ README.md           # setup đầy đủ: Supabase, Plaid, build 3 nền tảng, cron SQL
```

## 3. Quy ước kỹ thuật (đọc trước khi sửa code)

- **Sign convention (Plaid):** `transactions.amount` dương = tiền ra (chi), âm = tiền vào (thu).
- **Bảo mật token:** `plaid_items.access_token` client không đọc được (column-level grant).
  Mọi call Plaid chỉ nằm trong Edge Functions (service role).
- **Cron:** pg_cron gọi `plaid-sync` 12:00 UTC hàng ngày với header `x-cron-secret` —
  kiêm keep-alive chống Supabase free tier pause sau 7 ngày không hoạt động.
- **Config client:** `--dart-define=SUPABASE_URL` + `--dart-define=SUPABASE_ANON_KEY`.
- **Platform folders** (`android/`, `web/`, `windows/`...) không commit —
  chạy `flutter create . --platforms=web,windows,macos,linux,android` một lần sau khi clone.
- **Theme:** Data-Dense Dashboard, dark mặc định. Primary `#1E40AF`, accent `#059669`,
  destructive `#DC2626`, nền dark `#0F172A`. Font Fira Sans (UI) + Fira Code (số). Icon Lucide.
- **RLS:** mọi bảng lọc theo `auth.uid() = user_id`; category hệ thống có `user_id null` (read-only).

## 4. Trạng thái

<!-- Cập nhật mục này mỗi phiên -->

- [x] Design duyệt (2026-08-17) — spec trong `docs/superpowers/specs/`
- [x] Code MVP hoàn chỉnh, commit local `2e300eb` (branch `main`)
- [x] Push lên GitHub — branch `claude/code-review-github-commit-nbquvb` (merge vào `main` trên GitHub)
- [x] Code review toàn bộ MVP (2026-08-17) — kết quả trong nhật ký phiên bên dưới
- [x] Fix toàn bộ finding + security hardening (2026-08-17): migration 000002, link_tokens, unlink, escape search, CSV guard… Lưu ý: deploy `plaid-sync` với `--no-verify-jwt` (cron không có JWT)
- [x] Feature pack (2026-08-18): rules, recurring, net worth, split/note/tags, rollover, goals — migration 20260818000000 + redeploy Edge Functions khi setup
- [ ] Verify local: `flutter create .` → `flutter pub get` → `flutter analyze` → `flutter test`; `deno check` cho 4 file functions
- [ ] Tạo Supabase project + chạy 2 migration
- [ ] Deploy 3 Edge Functions + set secrets (`PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV`, `CRON_SECRET`)
- [ ] Đăng ký Plaid Trial plan, liên kết 2 bank thật
- [ ] Setup cron SQL (README mục 1.5)
- [ ] Deploy web lên Cloudflare Pages
- [ ] Build APK, cài lên điện thoại

## 5. Deferred có chủ đích (KHÔNG tự ý code)

Schema đã chừa chỗ, chỉ làm khi được yêu cầu:

- Verify JWS signature cho Plaid webhook (hiện tại: chỉ tin `item_id`, dùng để re-sync item đã có — an toàn ở mức MVP)
- Script export/backup DB định kỳ (free tier không có backup tự động)
- Multi-currency conversion, shared/family accounts, iOS, push notification (FCM), import CSV/OFX, cash-flow forecast, AI hỏi đáp (tốn phí API)

## 6. Nhật ký phiên

<!-- Thêm dòng mới mỗi phiên: ngày — việc đã làm — việc tiếp theo -->

| Ngày | Phiên | Đã làm | Tiếp theo |
|---|---|---|---|
| 2026-08-17 | Claude chat | Chốt ý tưởng, stack, tên, schema; build toàn bộ MVP (30 file); commit local `2e300eb`; đóng gói `monee-repo.tar.gz` | Push GitHub qua Claude Code; verify flutter analyze/test |
| 2026-08-17 | Claude Code | Review toàn bộ code; thêm `docs/CONTEXT.md`; push branch `claude/code-review-github-commit-nbquvb`. Phát hiện chính: (1) `plaid-link complete` không kiểm tra link_token thuộc về user gọi; (2) chuỗi search nội suy thẳng vào `.or()` PostgREST — dấu phẩy/ngoặc làm hỏng query; (3) `refreshData` không invalidate `_sixMonthTxnsProvider` (Reports bị stale sau khi sửa giao dịch); (4) xóa account Plaid để lại `plaid_items` mồ côi vẫn sync; (5) lỗi trong nút "Đã xong" của completeLink không được catch. Không phải blocker — chi tiết ở message phiên | Sửa các finding nếu muốn; verify flutter analyze/test; tạo Supabase project |
| 2026-08-18 | Claude Code | Feature pack (học từ Monarch/Copilot/YNAB/Simplifi): (1) rules tự phân loại — bảng `rules`, áp trong `syncItem` cho txn MỚI chưa có category, màn /settings/rules có "áp cho giao dịch cũ"; (2) recurring detection — `recurring_logic.dart` thuần (≥3 lần, chu kỳ tuần/tháng/năm, lọc gap + amount bất ổn), màn /transactions/recurring + card "Hóa đơn sắp tới" trên Dashboard; (3) net worth — bảng `balance_snapshots` ghi bởi plaid-sync (cron snapshot mọi user), line chart trong Báo cáo; (4) split txn (`parent_txn_id`, children thay parent trong mọi aggregation — `effectiveTxns`) + note/tags; (5) budget rollover (cộng dư 1 tháng trước, không âm); (6) goals — bảng `goals`, màn /budgets/goals, progress theo account hoặc nhập tay. Migration `20260818000000_features.sql`. CHƯA chạy flutter analyze/test (không có SDK) — **phải chạy trước khi build** | flutter analyze + test; chạy migration mới; redeploy 3 Edge Functions |
| 2026-08-18 | Claude Code | Light theme hoàn thiện (nền slate `#F1F5F9`, card trắng viền black-12 — toggle Tối/Sáng/Hệ thống đã có sẵn ở Settings từ trước). Fix bug routing: `buildRouter()` bị gọi lại mỗi lần rebuild (đổi theme là bị đá về /dashboard + leak auth listener) → `routerProvider` tạo router 1 lần. Audit routing & function linkage: mọi route/`context.go`/action Edge Function/tên bảng đều khớp | Chạy flutter analyze/test local |
| 2026-08-17 | Claude Code | Fix toàn bộ finding + rà bảo mật thêm. Mới phát hiện & sửa: cron pg_cron bị 401 vì `plaid-sync` deploy mặc định verify JWT (→ `--no-verify-jwt`, function tự xác thực); RLS cũ cho client gắn FK vào account/item/category của user khác (→ migration 000002 kiểm tra ownership trong policy, lỗi column-capture `accounts.plaid_item_id` trong subquery đã được security-review bắt và sửa, đã verify trên PG16); so sánh cron secret constant-time; CSV chống formula injection (kể cả `\r`). Đã `deno check` 4 file functions OK. Chưa chạy được `flutter analyze`/`test` (môi trường không có Flutter SDK) | Verify flutter analyze/test local; tạo Supabase project + chạy 3 migration; deploy functions theo README mới |
