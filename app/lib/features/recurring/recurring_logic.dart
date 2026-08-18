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

  DateTime get nextDue => _advance(lastDate, cadence);

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

/// Detects recurring charges among [txns] (split children excluded; income
/// included only when [includeIncome] — its items carry negative amounts).
/// Results are sorted by next due date.
List<RecurringItem> detectRecurring(Iterable<Txn> txns,
    {bool includeIncome = false}) {
  final groups = <String, List<Txn>>{};
  for (final t in txns) {
    if (t.amount == 0 || t.isSplitChild || t.isPending) continue;
    if (!includeIncome && t.amount < 0) continue;
    final name = (t.merchantName ?? t.description ?? '').trim().toLowerCase();
    if (name.isEmpty) continue;
    // Sign is part of the key so refunds don't pollute a charge's group.
    final key = '${t.amount > 0 ? '+' : '-'}|$name';
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

/// Month arithmetic that clamps to the target month's last day — otherwise
/// Jan 31 + 1 month overflows to Mar 3 and skips February entirely.
DateTime _addMonthsClamped(DateTime d, int months) {
  final lastDay = DateTime(d.year, d.month + months + 1, 0).day;
  return DateTime(d.year, d.month + months, d.day > lastDay ? lastDay : d.day);
}

DateTime _advance(DateTime d, Cadence c) => switch (c) {
      Cadence.weekly => d.add(const Duration(days: 7)),
      Cadence.monthly => _addMonthsClamped(d, 1),
      Cadence.yearly => _addMonthsClamped(d, 12),
    };

/// Projects a balance over the next [days] days by replaying recurring
/// charges (amount > 0 lowers the balance) and income (amount < 0 raises
/// it) from their next due dates. Returns step points, first at [from] and
/// last at the horizon.
List<({DateTime date, double balance})> forecastBalance({
  required double startBalance,
  required Iterable<RecurringItem> items,
  required DateTime from,
  int days = 30,
}) {
  final start = DateTime(from.year, from.month, from.day);
  final end = start.add(Duration(days: days));
  final events = <({DateTime date, double amount})>[];
  for (final it in items) {
    var d = it.nextDue;
    var guard = 0; // overdue items far in the past must not loop forever
    while (d.isBefore(start) && guard++ < 200) {
      d = _advance(d, it.cadence);
    }
    while (!d.isAfter(end) && guard++ < 200) {
      events.add((date: d, amount: it.amount));
      d = _advance(d, it.cadence);
    }
  }
  events.sort((a, b) => a.date.compareTo(b.date));

  var bal = startBalance;
  final points = <({DateTime date, double balance})>[
    (date: start, balance: bal),
  ];
  for (final e in events) {
    bal -= e.amount;
    points.add((date: e.date, balance: bal));
  }
  points.add((date: end, balance: bal));
  return points;
}

/// Lowest projected balance in a forecast.
double minForecastBalance(List<({DateTime date, double balance})> points) =>
    points.fold(double.infinity, (m, p) => p.balance < m ? p.balance : m);
