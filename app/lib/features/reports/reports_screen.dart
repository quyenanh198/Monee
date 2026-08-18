import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../budgets/budget_logic.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(sixMonthTxnsProvider);
    final categories = ref.watch(categoriesProvider);

    final snapshots = ref.watch(snapshotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo')),
      body: AsyncBody(
        value: txns,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState('Chưa có dữ liệu để báo cáo.');
          }

          final months = [
            for (var i = 5; i >= 0; i--) addMonths(DateTime.now(), -i)
          ];
          final byMonth = {
            for (final m in months)
              m: monthTotals(list.where((t) =>
                  t.date.year == m.year && t.date.month == m.month)),
          };
          final thisMonth = monthStart(DateTime.now());
          final t = byMonth[thisMonth]!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _NetWorthCard(snapshots: snapshots.valueOrNull ?? []),
              Row(children: [
                Expanded(
                  child: KpiCard(
                    label: 'Thu tháng này',
                    value: money(t.income),
                    valueColor: MoneeColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KpiCard(
                    label: 'Chi tháng này',
                    value: money(t.expense),
                    valueColor: MoneeColors.destructive,
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Thu vs Chi — 6 tháng',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 220,
                        child: BarChart(
                          BarChartData(
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(),
                              topTitles: const AxisTitles(),
                              rightTitles: const AxisTitles(),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= months.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        monthLabel(months[i]).substring(0, 2),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups: [
                              for (var i = 0; i < months.length; i++)
                                BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: byMonth[months[i]]!.income,
                                    color: MoneeColors.accent,
                                    width: 8,
                                  ),
                                  BarChartRodData(
                                    toY: byMonth[months[i]]!.expense,
                                    color: MoneeColors.destructive,
                                    width: 8,
                                  ),
                                ]),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _CategoryBreakdown(
                txns: list
                    .where((x) =>
                        x.date.year == thisMonth.year &&
                        x.date.month == thisMonth.month)
                    .toList(),
                categories: categories.valueOrNull ?? [],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Net-worth history line — one point per daily balance snapshot.
class _NetWorthCard extends StatelessWidget {
  final List<BalanceSnapshot> snapshots;
  const _NetWorthCard({required this.snapshots});

  @override
  Widget build(BuildContext context) {
    if (snapshots.length < 2) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.primary;
    final first = snapshots.first;
    final last = snapshots.last;
    final delta = last.total - first.total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tài sản ròng',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(last.total), style: moneyStyle(context, size: 22)),
                  const SizedBox(width: 10),
                  Text(
                    '${delta >= 0 ? '+' : '-'}${money(delta.abs())} '
                    'từ ${shortDate(first.date)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: delta >= 0
                          ? MoneeColors.accent
                          : MoneeColors.destructive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 140,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(),
                      topTitles: AxisTitles(),
                      rightTitles: AxisTitles(),
                      bottomTitles: AxisTitles(),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < snapshots.length; i++)
                            FlSpot(i.toDouble(), snapshots[i].total),
                        ],
                        color: color,
                        barWidth: 2,
                        isCurved: false,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withValues(alpha: 0.10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(shortDate(first.date),
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(shortDate(last.date),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  final List<Txn> txns;
  final List<Category> categories;
  const _CategoryBreakdown({required this.txns, required this.categories});

  @override
  Widget build(BuildContext context) {
    final spent = spentByCategory(txns);
    if (spent.isEmpty) return const SizedBox.shrink();
    final names = {for (final c in categories) c.id: c.name};
    final entries = spent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (s, e) => s + e.value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Phân bổ chi tiêu tháng này',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: categoryColor(e.key), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(e.key.isEmpty
                        ? 'Chưa phân loại'
                        : names[e.key] ?? '?')),
                Text(
                  '${money(e.value)} · ${(e.value / total * 100).toStringAsFixed(0)}%',
                  style: moneyStyle(context, size: 13),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
