import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';
import 'recurring_logic.dart';
import 'recurring_providers.dart';

String _cadenceLabel(Cadence c) => switch (c) {
      Cadence.weekly => 'hằng tuần',
      Cadence.monthly => 'hằng tháng',
      Cadence.yearly => 'hằng năm',
    };

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(sixMonthTxnsProvider);
    final catNames = ref.watch(categoryNamesProvider);
    final totalBalance = (ref.watch(accountsProvider).valueOrNull ?? [])
        .where((a) => a.currency == 'USD') // ledger currency
        .fold(0.0, (s, a) => s + a.currentBalance);

    return Scaffold(
      appBar: AppBar(title: const Text('Chi định kỳ')),
      body: AsyncBody(
        value: txns,
        builder: (list) {
          final items = ref.watch(recurringItemsProvider);
          if (items.isEmpty) {
            return const EmptyState(
                'Chưa nhận diện được khoản chi định kỳ nào.\n'
                'Cần ít nhất 3 lần lặp lại với chu kỳ ổn định.');
          }
          final today = DateTime.now();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              KpiCard(
                label: 'Tổng chi định kỳ mỗi tháng (ước tính)',
                value: money(totalMonthlyCost(items)),
                valueColor: MoneeColors.destructive,
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  for (final it in items)
                    ListTile(
                      leading: const Icon(LucideIcons.repeat),
                      title: Text(it.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        _cadenceLabel(it.cadence),
                        if (it.categoryId != null &&
                            catNames[it.categoryId] != null)
                          catNames[it.categoryId]!,
                        '${it.occurrences} lần',
                      ].join(' · ')),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(money(it.amount),
                              style: moneyStyle(context, size: 14)),
                          const SizedBox(height: 2),
                          Text(
                            _dueLabel(it.nextDue, today),
                            style: TextStyle(
                              fontSize: 12,
                              color: it.nextDue
                                      .isBefore(today.add(const Duration(days: 3)))
                                  ? const Color(0xFFF59E0B)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              _ForecastCard(
                startBalance: totalBalance,
                items: ref.watch(recurringAllProvider),
              ),
              const SizedBox(height: 12),
              Text(
                'Nhận diện tự động từ giao dịch 6 tháng gần nhất — chỉ mang '
                'tính tham khảo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  String _dueLabel(DateTime due, DateTime today) {
    final days = DateTime(due.year, due.month, due.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (days < 0) return 'quá hạn ${-days} ngày';
    if (days == 0) return 'hôm nay';
    return 'còn $days ngày · ${shortDate(due)}';
  }
}

/// Balance rendering: negatives keep their minus sign (money() is for
/// transaction amounts, whose sign convention is inverted).
String _bal(double v) => '${v < 0 ? '-' : ''}${money(v.abs())}';

/// 30-day balance projection from the detected recurring charges/income.
class _ForecastCard extends StatelessWidget {
  final double startBalance;
  final List<RecurringItem> items;
  const _ForecastCard({required this.startBalance, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final points = forecastBalance(
      startBalance: startBalance,
      items: items,
      from: DateTime.now(),
    );
    if (points.length < 3) return const SizedBox.shrink();
    final minBal = minForecastBalance(points);
    final start = points.first.date;
    final color = minBal < 0
        ? MoneeColors.destructive
        : Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Dự báo số dư 30 ngày',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Thấp nhất ${_bal(minBal)} · cuối kỳ ${_bal(points.last.balance)}',
            style: TextStyle(
                fontSize: 12.5,
                color: minBal < 0 ? MoneeColors.destructive : null),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
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
                      for (final p in points)
                        FlSpot(
                            p.date.difference(start).inDays.toDouble(),
                            p.balance),
                    ],
                    color: color,
                    barWidth: 2,
                    isCurved: false,
                    isStepLineChart: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                        show: true, color: color.withValues(alpha: 0.10)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(shortDate(points.first.date),
                style: Theme.of(context).textTheme.bodySmall),
            Text(shortDate(points.last.date),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
      ),
    );
  }
}
