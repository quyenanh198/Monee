import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      appBar: AppBar(title: const Text('Giao dịch')),
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
  var isExpense = existing?.isExpense ?? true;
  var date = existing?.date ?? DateTime.now();
  var accountId = existing?.accountId ?? accounts.first.id;
  String? categoryId = existing?.categoryId;

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
              if (plaidRow) {
                await setTxnCategory(db, existing.id, categoryId);
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
