/// Pure functions for budget and report math. No Flutter imports — unit-tested.
library;

import '../../models/models.dart';

/// Drops split parents: when a txn's id is referenced as parent by another
/// txn in the set, the parent is replaced by its children in every
/// aggregation (children carry the categories; their sum equals the parent).
Iterable<Txn> effectiveTxns(Iterable<Txn> txns) {
  final parentIds = <String>{
    for (final t in txns)
      if (t.parentTxnId != null) t.parentTxnId!,
  };
  if (parentIds.isEmpty) return txns;
  return txns.where((t) => !parentIds.contains(t.id));
}

/// Total spent (amount > 0 only) per category id. Uncategorized under key ''.
Map<String, double> spentByCategory(Iterable<Txn> txns) {
  final out = <String, double>{};
  for (final t in effectiveTxns(txns)) {
    if (t.amount <= 0) continue; // income/transfers-in don't count as spend
    final key = t.categoryId ?? '';
    out[key] = (out[key] ?? 0) + t.amount;
  }
  return out;
}

/// (income, expense) totals for a set of transactions.
/// Expense = sum of positive amounts; income = sum of |negative amounts|.
({double income, double expense}) monthTotals(Iterable<Txn> txns) {
  double income = 0, expense = 0;
  for (final t in effectiveTxns(txns)) {
    if (t.amount > 0) {
      expense += t.amount;
    } else {
      income += -t.amount;
    }
  }
  return (income: income, expense: expense);
}

/// Leftover a rollover budget carries into the next month (never negative).
double rolloverCarry({required double prevBudget, required double prevSpent}) {
  final left = prevBudget - prevSpent;
  return left > 0 ? left : 0;
}

/// Budget progress in [0, 1]; a zero budget with any spend counts as fully used.
double budgetProgress(double spent, double budget) {
  if (budget <= 0) return spent > 0 ? 1 : 0;
  final p = spent / budget;
  return p < 0 ? 0 : (p > 1 ? 1 : p);
}

enum BudgetStatus { ok, warning, over }

/// warning at >= 80% used, over at > 100%.
BudgetStatus budgetStatus(double spent, double budget) {
  if (budget <= 0) return spent > 0 ? BudgetStatus.over : BudgetStatus.ok;
  final p = spent / budget;
  if (p > 1) return BudgetStatus.over;
  if (p >= 0.8) return BudgetStatus.warning;
  return BudgetStatus.ok;
}

/// Sum of budgets for a month.
double totalBudget(Iterable<Budget> budgets) =>
    budgets.fold(0.0, (sum, b) => sum + b.amount);
