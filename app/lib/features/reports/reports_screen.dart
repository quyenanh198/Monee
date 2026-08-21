import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../budgets/budget_logic.dart';

/// Report period: this month vs this calendar year.
final _yearModeProvider = StateProvider<bool>((_) => false);

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(sixMonthTxnsProvider);
    final categories = ref.watch(categoriesProvider);
    final snapshots = ref.watch(snapshotsProvider);
    final yearMode = ref.watch(_yearModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('Tháng')),
                ButtonSegment(value: true, label: Text('Năm')),
              ],
              selected: {yearMode},
              onSelectionChanged: (s) =>
                  ref.read(_yearModeProvider.notifier).state = s.first,
            ),
          ),
        ],
      ),
      body: AsyncBody(
        value: txns,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState('Chưa có dữ liệu để báo cáo.');
          }

          final now = DateTime.now();
          final months = [
            for (var i = 5; i >= 0; i--) addMonths(now, -i)
          ];
          final byMonth = {
            for (final m in months)
              m: monthTotals(list.where(
                  (t) => t.date.year == m.year && t.date.month == m.month)),
          };
          final thisMonth = monthStart(now);
          final t = byMonth[thisMonth]!;

          // Period scope for the category donut/top list.
          final periodTxns = yearMode
              ? list.where((x) => x.date.year == now.year).toList()
              : list
                  .where((x) =>
                      x.date.year == thisMonth.year &&
                      x.date.month == thisMonth.month)
                  .toList();
          final periodLabel =
              yearMode ? 'năm ${now.year}' : 'tháng ${monthLabel(thisMonth)}';

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
              _SpendingDonut(
                txns: periodTxns,
                categories: categories.valueOrNull ?? [],
                periodLabel: periodLabel,
              ),
              const SizedBox(height: 16),
              _TrendsCard(months: months, byMonth: byMonth),
              const SizedBox(height: 16),
              _TopCategories(
                txns: periodTxns,
                categories: categories.valueOrNull ?? [],
              ),
              const SizedBox(height: 16),
              _SpendingInsight(byMonth: byMonth, months: months),
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

/// Donut with the period total in the center + legend with amount and %.
class _SpendingDonut extends StatelessWidget {
  final List<Txn> txns;
  final List<Category> categories;
  final String periodLabel;
  const _SpendingDonut(
      {required this.txns,
      required this.categories,
      required this.periodLabel});

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
          Row(children: [
            Expanded(
              child: Text('Chi tiêu theo danh mục',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Text(periodLabel,
                style: TextStyle(fontSize: 12.5, color: mutedColor(context))),
          ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 460;
            final donut = SizedBox(
              height: 190,
              width: wide ? 220 : null,
              child: Stack(alignment: Alignment.center, children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 56,
                    sectionsSpace: 2,
                    sections: [
                      for (final e in entries)
                        PieChartSectionData(
                          value: e.value,
                          color: categoryColor(e.key),
                          showTitle: false,
                          radius: 32,
                        ),
                    ],
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(money(total), style: moneyStyle(context, size: 17)),
                  Text('Tổng chi',
                      style: TextStyle(
                          fontSize: 12, color: mutedColor(context))),
                ]),
              ]),
            );
            final legend = Column(children: [
              for (final e in entries.take(7))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: categoryColor(e.key),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            e.key.isEmpty
                                ? 'Chưa phân loại'
                                : names[e.key] ?? '?',
                            style: const TextStyle(fontSize: 13.5))),
                    Text(money(e.value), style: moneyStyle(context, size: 13)),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(e.value / total * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12.5, color: mutedColor(context)),
                      ),
                    ),
                  ]),
                ),
            ]);
            if (wide) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                donut,
                const SizedBox(width: 20),
                Expanded(child: legend),
              ]);
            }
            return Column(children: [donut, const SizedBox(height: 12), legend]);
          }),
        ]),
      ),
    );
  }
}

/// 6-month income vs expense bars.
class _TrendsCard extends StatelessWidget {
  final List<DateTime> months;
  final Map<DateTime, ({double expense, double income})> byMonth;
  const _TrendsCard({required this.months, required this.byMonth});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Xu hướng 6 tháng',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Row(children: [
              _legendDot(MoneeColors.accent, 'Thu'),
              const SizedBox(width: 12),
              _legendDot(MoneeColors.destructive, 'Chi'),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
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
                          borderRadius: BorderRadius.circular(3),
                        ),
                        BarChartRodData(
                          toY: byMonth[months[i]]!.expense,
                          color: MoneeColors.destructive,
                          width: 8,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

/// Top spending categories as progress bars against the biggest one.
class _TopCategories extends StatelessWidget {
  final List<Txn> txns;
  final List<Category> categories;
  const _TopCategories({required this.txns, required this.categories});

  @override
  Widget build(BuildContext context) {
    final spent = spentByCategory(txns);
    if (spent.isEmpty) return const SizedBox.shrink();
    final names = {for (final c in categories) c.id: c.name};
    final icons = {for (final c in categories) c.id: c.icon};
    final entries = spent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (s, e) => s + e.value);
    final top = entries.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Danh mục hàng đầu',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final e in top)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: categoryColor(e.key).withValues(alpha: 0.14),
                  ),
                  child: Icon(categoryIcon(icons[e.key]),
                      size: 16, color: categoryColor(e.key)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                                e.key.isEmpty
                                    ? 'Chưa phân loại'
                                    : names[e.key] ?? '?',
                                style: const TextStyle(fontSize: 13.5)),
                          ),
                          Text(money(e.value),
                              style: moneyStyle(context, size: 13)),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${(e.value / total * 100).toStringAsFixed(0)}%',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12, color: mutedColor(context)),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: e.value / top.first.value,
                            minHeight: 6,
                            color: categoryColor(e.key),
                            backgroundColor: categoryColor(e.key)
                                .withValues(alpha: 0.12),
                          ),
                        ),
                      ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Rule-based insight: this month's spending vs the previous month.
class _SpendingInsight extends StatelessWidget {
  final List<DateTime> months;
  final Map<DateTime, ({double expense, double income})> byMonth;
  const _SpendingInsight({required this.months, required this.byMonth});

  @override
  Widget build(BuildContext context) {
    if (months.length < 2) return const SizedBox.shrink();
    final cur = byMonth[months.last]!.expense;
    final prev = byMonth[months[months.length - 2]]!.expense;
    if (prev <= 0 || cur <= 0) return const SizedBox.shrink();
    final pct = (cur - prev) / prev * 100;
    final lower = pct <= 0;
    final color = lower ? MoneeColors.accent : MoneeColors.warning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(
                lower ? LucideIcons.trendingDown : LucideIcons.trendingUp,
                size: 20,
                color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Insight chi tiêu',
                  style: Theme.of(context).textTheme.titleSmall),
              Text(
                lower
                    ? 'Bạn chi ít hơn ${pct.abs().toStringAsFixed(0)}% so với tháng trước. Rất tốt!'
                    : 'Chi tiêu đang cao hơn ${pct.abs().toStringAsFixed(0)}% so với tháng trước.',
                style: TextStyle(fontSize: 13, color: mutedColor(context)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
