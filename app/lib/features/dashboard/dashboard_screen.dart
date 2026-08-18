import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../budgets/budget_logic.dart';
import '../recurring/recurring_logic.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final month = monthStart(DateTime.now());
    final monthTxns = ref.watch(monthTxnsProvider(month));
    final recent = ref.watch(recentTxnsProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tổng quan'),
        actions: [
          IconButton(
            tooltip: 'Tài khoản',
            icon: const Icon(LucideIcons.landmark),
            onPressed: () => context.go('/dashboard/accounts'),
          ),
          IconButton(
            tooltip: 'Đồng bộ ngân hàng',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(plaidServiceProvider).syncNow();
                refreshData(ref);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Đồng bộ xong')));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshData(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AsyncBody(
              value: accounts,
              builder: (list) {
                final total =
                    list.fold(0.0, (s, a) => s + a.currentBalance);
                return Row(children: [
                  Expanded(
                      child: KpiCard(
                          label: 'Tổng số dư', value: money(total))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AsyncBody(
                      value: monthTxns,
                      builder: (txns) {
                        final t = monthTotals(txns);
                        return KpiCard(
                          label: 'Chi tháng ${monthLabel(month)}',
                          value: money(t.expense),
                          valueColor: MoneeColors.destructive,
                        );
                      },
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 16),
            _SpendDonut(monthTxns: monthTxns, categories: categories),
            _UpcomingBills(sixMonth: ref.watch(sixMonthTxnsProvider)),
            const SizedBox(height: 16),
            Text('Giao dịch gần đây',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AsyncBody(
              value: recent,
              builder: (txns) => txns.isEmpty
                  ? const EmptyState(
                      'Chưa có giao dịch. Liên kết ngân hàng hoặc thêm tay.')
                  : Card(
                      child: Column(children: [
                        for (final t in txns)
                          TxnTile(
                            txn: t,
                            categoryName: categories.valueOrNull
                                ?.where((c) => c.id == t.categoryId)
                                .firstOrNull
                                ?.name,
                          ),
                      ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recurring charges due in the next 14 days, detected from recent history.
class _UpcomingBills extends StatelessWidget {
  final AsyncValue<List<Txn>> sixMonth;
  const _UpcomingBills({required this.sixMonth});

  @override
  Widget build(BuildContext context) {
    final txns = sixMonth.valueOrNull;
    if (txns == null) return const SizedBox.shrink();
    final today = DateTime.now();
    final horizon = today.add(const Duration(days: 14));
    final due = detectRecurring(txns)
        .where((i) => i.nextDue.isBefore(horizon))
        .take(4)
        .toList();
    if (due.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Hóa đơn sắp tới',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => context.go('/transactions/recurring'),
                  child: const Text('Tất cả'),
                ),
              ]),
              for (final i in due)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 8),
                  child: Row(children: [
                    const Icon(LucideIcons.repeat, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(i.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text(shortDate(i.nextDue),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 12),
                    Text(money(i.amount),
                        style: moneyStyle(context, size: 13.5)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpendDonut extends StatelessWidget {
  final AsyncValue<List<Txn>> monthTxns;
  final AsyncValue<List<Category>> categories;
  const _SpendDonut({required this.monthTxns, required this.categories});

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      value: monthTxns,
      builder: (txns) {
        final spent = spentByCategory(txns);
        if (spent.isEmpty) {
          return const SizedBox.shrink();
        }
        final catNames = {
          for (final c in categories.valueOrNull ?? <Category>[]) c.id: c.name
        };
        final entries = spent.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chi tiêu theo danh mục',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 45,
                      sectionsSpace: 2,
                      sections: [
                        for (final e in entries)
                          PieChartSectionData(
                            value: e.value,
                            color: categoryColor(e.key),
                            showTitle: false,
                            radius: 40,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    for (final e in entries.take(6))
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: categoryColor(e.key),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(
                            '${e.key.isEmpty ? 'Chưa phân loại' : catNames[e.key] ?? '?'} · ${money(e.value)}'),
                      ]),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
