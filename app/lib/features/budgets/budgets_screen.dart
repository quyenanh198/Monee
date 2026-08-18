import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
            tooltip: 'Mục tiêu tiết kiệm',
            icon: const Icon(LucideIcons.target),
            onPressed: () => context.go('/budgets/goals'),
          ),
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
          // Rollover: leftover from last month's budget for the same
          // category is added on top of this month's amount.
          final prevMonth = addMonths(month, -1);
          final prevSpent = spentByCategory(
              ref.watch(monthTxnsProvider(prevMonth)).valueOrNull ?? []);
          final prevBudgets = {
            for (final b
                in ref.watch(budgetsProvider(prevMonth)).valueOrNull ?? [])
              b.categoryId: b.amount,
          };
          double carryOf(Budget b) => b.rollover
              ? rolloverCarry(
                  prevBudget: prevBudgets[b.categoryId] ?? 0,
                  prevSpent: prevSpent[b.categoryId] ?? 0)
              : 0.0;
          final effectiveTotal =
              buds.fold(0.0, (s, b) => s + b.amount + carryOf(b));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              KpiCard(
                label: 'Tổng ngân sách tháng (gồm cộng dồn)',
                value: money(effectiveTotal),
              ),
              const SizedBox(height: 12),
              for (final b in buds)
                _BudgetTile(
                  name: catNames[b.categoryId] ?? '?',
                  spent: spent[b.categoryId] ?? 0,
                  budget: b.amount + carryOf(b),
                  carry: carryOf(b),
                  onTap: () => _editBudget(context, ref,
                      month: month,
                      cats: catList,
                      categoryId: b.categoryId,
                      current: b.amount,
                      currentRollover: b.rollover,
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
    bool currentRollover = false,
    String? budgetId,
  }) async {
    final amount =
        TextEditingController(text: current?.toStringAsFixed(0) ?? '');
    String? selected = categoryId ?? (cats.isEmpty ? null : cats.first.id);
    var rollover = currentRollover;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
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
          const SizedBox(height: 8),
          SwitchListTile(
            value: rollover,
            contentPadding: EdgeInsets.zero,
            title: const Text('Cộng dồn phần dư sang tháng sau',
                style: TextStyle(fontSize: 14)),
            onChanged: (v) => setState(() => rollover = v),
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
                rollover: rollover,
              );
              ref.invalidate(budgetsProvider);
              nav.pop();
            },
            child: const Text('Lưu'),
          ),
        ],
        ),
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  final String name;
  final double spent;
  final double budget; // effective budget = amount + carry
  final double carry;
  final VoidCallback onTap;
  const _BudgetTile(
      {required this.name,
      required this.spent,
      required this.budget,
      this.carry = 0,
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
            if (carry > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('gồm ${money(carry)} cộng dồn từ tháng trước',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
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
