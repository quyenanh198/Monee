import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';
import 'recurring_logic.dart';

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
    final categories = ref.watch(categoriesProvider);
    final catNames = {
      for (final c in categories.valueOrNull ?? []) c.id: c.name
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Chi định kỳ')),
      body: AsyncBody(
        value: txns,
        builder: (list) {
          final items = detectRecurring(list);
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
