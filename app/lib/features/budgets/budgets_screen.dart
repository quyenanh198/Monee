import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'budget_logic.dart';

final _budgetMonthProvider =
    StateProvider<DateTime>((_) => monthStart(DateTime.now()));

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_budgetMonthProvider);
    final budgets = ref.watch(budgetsProvider(month));
    final txns = ref.watch(monthTxnsProvider(month));
    final categories = ref.watch(categoriesProvider);

    final catList = categories.valueOrNull ?? [];
    final catNames = {for (final c in catList) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ngân sách'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => ref
                .read(_budgetMonthProvider.notifier)
                .update((m) => addMonths(m, -1)),
          ),
          Center(child: Text(monthLabel(month))),
          IconButton(
            icon: const Icon(LucideIcons.chevronRight),
            onPressed: () => ref
                .read(_budgetMonthProvider.notifier)
                .update((m) => addMonths(m, 1)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Đặt ngân sách',
        onPressed: catList.isEmpty
            ? null
            : () => _editBudget(context, ref, month: month, cats: catList),
        child: const Icon(LucideIcons.plus),
      ),
      body: AsyncBody(
        value: budgets,
        builder: (buds) {
          final spent = spentByCategory(txns.valueOrNull ?? []);
          if (buds.isEmpty) {
            return const EmptyState(
                'Chưa đặt ngân sách cho tháng này. Bấm + để thêm.');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              KpiCard(
                label: 'Tổng ngân sách tháng',
                value: money(totalBudget(buds)),
              ),
              const SizedBox(height: 12),
              for (final b in buds)
                _BudgetTile(
                  name: catNames[b.categoryId] ?? '?',
                  spent: spent[b.categoryId] ?? 0,
                  budget: b.amount,
                  onTap: () => _editBudget(context, ref,
                      month: month,
                      cats: catList,
                      categoryId: b.categoryId,
                      current: b.amount,
                      budgetId: b.id),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editBudget(
    BuildContext context,
    WidgetRef ref, {
    required DateTime month,
    required List<Category> cats,
    String? categoryId,
    double? current,
    String? budgetId,
  }) async {
    final amount =
        TextEditingController(text: current?.toStringAsFixed(0) ?? '');
    String? selected = categoryId ?? (cats.isEmpty ? null : cats.first.id);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(budgetId == null ? 'Đặt ngân sách' : 'Sửa ngân sách'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Danh mục'),
            items: [
              for (final c in cats)
                DropdownMenuItem<String>(value: c.id, child: Text(c.name)),
            ],
            onChanged: budgetId == null ? (v) => selected = v : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            decoration:
                const InputDecoration(labelText: 'Số tiền / tháng (USD)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ]),
        actions: [
          if (budgetId != null)
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                await deleteBudget(ref.read(supabaseProvider), budgetId);
                ref.invalidate(budgetsProvider);
                nav.pop();
              },
              child: const Text('Xóa'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (selected == null) return;
              final nav = Navigator.of(ctx);
              await upsertBudget(
                ref.read(supabaseProvider),
                categoryId: selected!,
                month: month,
                amount: double.tryParse(amount.text) ?? 0,
              );
              ref.invalidate(budgetsProvider);
              nav.pop();
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  final String name;
  final double spent;
  final double budget;
  final VoidCallback onTap;
  const _BudgetTile(
      {required this.name,
      required this.spent,
      required this.budget,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = budgetStatus(spent, budget);
    final color = switch (status) {
      BudgetStatus.ok => MoneeColors.accent,
      BudgetStatus.warning => const Color(0xFFF59E0B),
      BudgetStatus.over => MoneeColors.destructive,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(name,
                      style: Theme.of(context).textTheme.titleSmall)),
              Text('${money(spent)} / ${money(budget)}',
                  style: moneyStyle(context, size: 14, color: color)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: budgetProgress(spent, budget),
                minHeight: 8,
                color: color,
              ),
            ),
            if (status == BudgetStatus.over)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Vượt ngân sách ${money(spent - budget)}',
                    style: TextStyle(color: color, fontSize: 12)),
              ),
          ]),
        ),
      ),
    );
  }
}
