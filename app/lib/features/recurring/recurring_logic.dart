/// Pure recurring-transaction detection. No Flutter imports — unit-tested.
///
/// Heuristic: group expenses by normalized merchant text; a group is
/// recurring when it has >= 3 occurrences, the median gap between charges
/// matches a known cadence, and most amounts sit near the median amount.
library;

import '../../models/models.dart';

enum Cadence { weekly, monthly, yearly }

class RecurringItem {
  final String name; // display name (original casing of latest txn)
  final String? categoryId; // category of the latest occurrence
  final double amount; // median charge
  final Cadence cadence;
  final DateTime lastDate;
  final int occurrences;

  const RecurringItem({
    required this.name,
    required this.categoryId,
    required this.amount,
    required this.cadence,
    required this.lastDate,
    required this.occurrences,
  });

  DateTime get nextDue => switch (cadence) {
        Cadence.weekly => lastDate.add(const Duration(days: 7)),
        Cadence.monthly =>
          DateTime(lastDate.year, lastDate.month + 1, lastDate.day),
        Cadence.yearly =>
          DateTime(lastDate.year + 1, lastDate.month, lastDate.day),
      };

  /// Cost normalized to one month.
  double get monthlyCost => switch (cadence) {
        Cadence.weekly => amount * 52 / 12,
        Cadence.monthly => amount,
        Cadence.yearly => amount / 12,
      };
}

double _median(List<double> sorted) {
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

Cadence? _cadenceForGap(double days) {
  if (days >= 6 && days <= 8) return Cadence.weekly;
  if (days >= 25 && days <= 35) return Cadence.monthly;
  if (days >= 350 && days <= 380) return Cadence.yearly;
  return null;
}

/// Detects recurring charges among [txns] (expenses only, split children
/// excluded). Results are sorted by next due date.
List<RecurringItem> detectRecurring(Iterable<Txn> txns) {
  final groups = <String, List<Txn>>{};
  for (final t in txns) {
    if (t.amount <= 0 || t.isSplitChild || t.isPending) continue;
    final key = (t.merchantName ?? t.description ?? '').trim().toLowerCase();
    if (key.isEmpty) continue;
    (groups[key] ??= []).add(t);
  }

  final items = <RecurringItem>[];
  for (final group in groups.values) {
    if (group.length < 3) continue;
    group.sort((a, b) => a.date.compareTo(b.date));

    final gaps = <double>[
      for (var i = 1; i < group.length; i++)
        group[i].date.difference(group[i - 1].date).inDays.toDouble(),
    ]..sort();
    final cadence = _cadenceForGap(_median(gaps));
    if (cadence == null) continue;
    // The median alone can mask irregular gaps ([10, 50] → median 30):
    // most individual gaps must also fit the cadence.
    final inRange = gaps.where((g) => _cadenceForGap(g) == cadence).length;
    if (inRange < (gaps.length * 0.6).ceil()) continue;

    final amounts = group.map((t) => t.amount).toList()..sort();
    final med = _median(amounts);
    final tolerance = med.abs() * 0.3 < 1.0 ? 1.0 : med.abs() * 0.3;
    final stable =
        group.where((t) => (t.amount - med).abs() <= tolerance).length;
    if (stable < (group.length * 0.6).ceil()) continue;

    final last = group.last;
    items.add(RecurringItem(
      name: last.title,
      categoryId: last.categoryId,
      amount: med,
      cadence: cadence,
      lastDate: last.date,
      occurrences: group.length,
    ));
  }

  items.sort((a, b) => a.nextDue.compareTo(b.nextDue));
  return items;
}

/// Total monthly cost of all recurring items.
double totalMonthlyCost(Iterable<RecurringItem> items) =>
    items.fold(0.0, (s, i) => s + i.monthlyCost);
