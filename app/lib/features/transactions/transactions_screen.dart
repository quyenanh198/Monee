import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    final filter = ref.watch(txnFilterProvider);
    final pageSize = ref.watch(txnPageSizeProvider);

    final accList = accounts.valueOrNull ?? [];
    final catList = categories.valueOrNull ?? [];
    final catNames = {for (final c in catList) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giao dịch'),
        actions: [
          IconButton(
            tooltip: 'Chi định kỳ',
            icon: const Icon(LucideIcons.repeat),
            onPressed: () => context.go('/transactions/recurring'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Thêm giao dịch',
        onPressed: accList.isEmpty
            ? null
            : () => showTxnForm(context, ref, accounts: accList, cats: catList),
        child: const Icon(LucideIcons.plus),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Tìm kiếm',
                  prefixIcon: Icon(LucideIcons.search, size: 18),
                ),
                onSubmitted: (v) => ref
                    .read(txnFilterProvider.notifier)
                    .update((f) => f.copyWith(search: v.trim())),
              ),
            ),
            _drop<String?>(
              label: 'Tài khoản',
              value: filter.accountId,
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả')),
                for (final a in accList)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => ref
                  .read(txnFilterProvider.notifier)
                  .update((f) => f.copyWith(accountId: () => v)),
            ),
            _drop<String?>(
              label: 'Danh mục',
              value: filter.categoryId,
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả')),
                for (final c in catList)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => ref
                  .read(txnFilterProvider.notifier)
                  .update((f) => f.copyWith(categoryId: () => v)),
            ),
            _drop<DateTime?>(
              label: 'Tháng',
              value: filter.month,
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả')),
                for (var i = 0; i < 12; i++)
                  DropdownMenuItem(
                    value: addMonths(DateTime.now(), -i),
                    child: Text(monthLabel(addMonths(DateTime.now(), -i))),
                  ),
              ],
              onChanged: (v) => ref
                  .read(txnFilterProvider.notifier)
                  .update((f) => f.copyWith(month: () => v)),
            ),
          ]),
        ),
        Expanded(
          child: AsyncBody(
            value: txns,
            builder: (list) => list.isEmpty
                ? const EmptyState('Không có giao dịch khớp bộ lọc.')
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Column(children: [
                          for (final t in list)
                            TxnTile(
                              txn: t,
                              categoryName: catNames[t.categoryId],
                              onTap: () => showTxnForm(context, ref,
                                  accounts: accList, cats: catList, existing: t),
                            ),
                        ]),
                      ),
                      if (list.length >= pageSize)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton(
                            onPressed: () => ref
                                .read(txnPageSizeProvider.notifier)
                                .update((n) => n + 100),
                            child: const Text('Tải thêm'),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _drop<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

/// Add/edit form. Plaid rows: only the category is editable; manual rows: full edit.
Future<void> showTxnForm(
  BuildContext context,
  WidgetRef ref, {
  required List<Account> accounts,
  required List<Category> cats,
  Txn? existing,
}) async {
  final plaidRow = existing != null && !existing.isManual;
  final amount = TextEditingController(
      text: existing?.amount.abs().toStringAsFixed(2) ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final note = TextEditingController(text: existing?.note ?? '');
  final tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
  var isExpense = existing?.isExpense ?? true;
  var date = existing?.date ?? DateTime.now();
  var accountId = existing?.accountId ?? accounts.first.id;
  String? categoryId = existing?.categoryId;

  List<String> parseTags() => tags.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null
            ? 'Thêm giao dịch'
            : (plaidRow ? 'Phân loại giao dịch' : 'Sửa giao dịch')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (plaidRow)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(existing.title,
                    style: Theme.of(ctx).textTheme.bodyMedium),
              ),
            if (!plaidRow) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Chi')),
                  ButtonSegment(value: false, label: Text('Thu')),
                ],
                selected: {isExpense},
                onSelectionChanged: (s) => setState(() => isExpense = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                decoration: const InputDecoration(labelText: 'Số tiền'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Mô tả'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Tài khoản'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => accountId = v ?? accountId,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(LucideIcons.calendar, size: 18),
                label: Text(shortDate(date)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => date = picked);
                },
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String?>(
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Danh mục'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Chưa phân loại')),
                for (final c in cats)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => categoryId = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tags,
              decoration: const InputDecoration(
                  labelText: 'Tags', helperText: 'Cách nhau bằng dấu phẩy'),
            ),
            if (existing != null && !existing.isSplitChild) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(LucideIcons.scissors, size: 18),
                  label: const Text('Tách giao dịch'),
                  onPressed: () async {
                    final nav = Navigator.of(ctx);
                    final done =
                        await showSplitDialog(ctx, ref, existing, cats);
                    if (done) nav.pop();
                  },
                ),
              ),
            ],
          ]),
        ),
        actions: [
          if (existing != null && !plaidRow)
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                await deleteTxn(ref.read(supabaseProvider), existing.id);
                refreshData(ref);
                nav.pop();
              },
              child: const Text('Xóa'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final db = ref.read(supabaseProvider);
              final noteVal = note.text.trim().isEmpty ? null : note.text.trim();
              if (plaidRow) {
                await updateTxnMeta(db, existing.id,
                    categoryId: categoryId, note: noteVal, tags: parseTags());
              } else {
                final raw = double.tryParse(amount.text) ?? 0;
                await upsertManualTxn(
                  db,
                  id: existing?.id,
                  accountId: accountId,
                  amount: isExpense ? raw.abs() : -raw.abs(),
                  date: date,
                  description: description.text.trim().isEmpty
                      ? null
                      : description.text.trim(),
                  categoryId: categoryId,
                  note: noteVal,
                  tags: parseTags(),
                );
              }
              refreshData(ref);
              nav.pop();
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    ),
  );
}

/// Split [parent] into 2+ parts whose amounts must sum to the original.
/// Re-splitting replaces the previous parts. Returns true when saved.
Future<bool> showSplitDialog(
  BuildContext context,
  WidgetRef ref,
  Txn parent,
  List<Category> cats,
) async {
  final total = parent.amount.abs();
  final sign = parent.amount >= 0 ? 1 : -1;
  final amounts = [TextEditingController(), TextEditingController()];
  final catIds = <String?>[parent.categoryId, null];
  var saved = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final entered = amounts
            .map((c) => double.tryParse(c.text) ?? 0)
            .fold(0.0, (s, v) => s + v);
        final remaining = total - entered;

        return AlertDialog(
          title: const Text('Tách giao dịch'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${parent.title} · ${money(total)}',
                  style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 12),
              for (var i = 0; i < amounts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: amounts[i],
                        decoration: InputDecoration(labelText: 'Phần ${i + 1}'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: catIds[i],
                        decoration:
                            const InputDecoration(labelText: 'Danh mục'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Chưa phân loại')),
                          for (final c in cats)
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => catIds[i] = v,
                      ),
                    ),
                  ]),
                ),
              TextButton.icon(
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Thêm phần'),
                onPressed: () => setState(() {
                  amounts.add(TextEditingController());
                  catIds.add(null);
                }),
              ),
              const SizedBox(height: 4),
              Text(
                remaining.abs() < 0.005
                    ? 'Đủ ${money(total)}'
                    : 'Còn thiếu ${money(remaining)}',
                style: TextStyle(
                  fontSize: 13,
                  color: remaining.abs() < 0.005
                      ? null
                      : Theme.of(ctx).colorScheme.error,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: remaining.abs() >= 0.005
                  ? null
                  : () async {
                      final nav = Navigator.of(ctx);
                      final db = ref.read(supabaseProvider);
                      final parts = <({double amount, String? categoryId})>[
                        for (var i = 0; i < amounts.length; i++)
                          if ((double.tryParse(amounts[i].text) ?? 0) > 0)
                            (
                              amount: sign *
                                  (double.tryParse(amounts[i].text) ?? 0),
                              categoryId: catIds[i],
                            ),
                      ];
                      if (parts.length < 2) return;
                      await unsplitTxn(db, parent.id);
                      await splitTxn(db, parent, parts);
                      refreshData(ref);
                      saved = true;
                      nav.pop();
                    },
              child: const Text('Tách'),
            ),
          ],
        );
      },
    ),
  );
  return saved;
}
