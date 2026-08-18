import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories.dart';
import 'recurring_logic.dart';

/// Detection is O(n log n) over six months of transactions — derive it once
/// per data change instead of re-running it inside every build().

/// Recurring charges (expenses only — what the recurring screen lists).
final recurringItemsProvider = Provider<List<RecurringItem>>((ref) {
  final txns = ref.watch(sixMonthTxnsProvider).valueOrNull;
  return txns == null ? const [] : detectRecurring(txns);
});

/// Charges AND income (payroll) — what the cash-flow forecast replays.
final recurringAllProvider = Provider<List<RecurringItem>>((ref) {
  final txns = ref.watch(sixMonthTxnsProvider).valueOrNull;
  return txns == null ? const [] : detectRecurring(txns, includeIncome: true);
});
