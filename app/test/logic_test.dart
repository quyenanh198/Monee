import 'package:flutter_test/flutter_test.dart';
import 'package:monee/features/budgets/budget_logic.dart';
import 'package:monee/features/recurring/recurring_logic.dart';
import 'package:monee/features/settings/csv_export.dart';
import 'package:monee/models/models.dart';

Txn txn({
  String id = 'id',
  double amount = 10,
  String? categoryId,
  String accountId = 'acc1',
  DateTime? date,
  String? merchant,
  String? description,
  String? parentTxnId,
}) =>
    Txn(
      id: id,
      accountId: accountId,
      plaidTransactionId: null,
      amount: amount,
      currency: 'USD',
      date: date ?? DateTime(2026, 8, 15),
      merchantName: merchant,
      description: description,
      categoryId: categoryId,
      isPending: false,
      parentTxnId: parentTxnId,
    );

void main() {
  group('spentByCategory', () {
    test('sums positive amounts per category, income excluded', () {
      final spent = spentByCategory([
        txn(amount: 10, categoryId: 'food'),
        txn(amount: 5.5, categoryId: 'food'),
        txn(amount: 20, categoryId: 'rent'),
        txn(amount: -100, categoryId: 'food'), // income — ignored
      ]);
      expect(spent['food'], closeTo(15.5, 0.001));
      expect(spent['rent'], 20);
    });

    test('uncategorized grouped under empty key', () {
      final spent = spentByCategory([txn(amount: 7)]);
      expect(spent[''], 7);
    });
  });

  group('monthTotals', () {
    test('splits income and expense with Plaid sign convention', () {
      final t = monthTotals([
        txn(amount: 30), // expense
        txn(amount: -1000), // income
        txn(amount: 20),
      ]);
      expect(t.expense, 50);
      expect(t.income, 1000);
    });
  });

  group('split transactions', () {
    test('parent is replaced by children in aggregations', () {
      final txns = [
        txn(id: 'p1', amount: 30), // split parent, uncategorized
        txn(id: 'c1', amount: 20, categoryId: 'food', parentTxnId: 'p1'),
        txn(id: 'c2', amount: 10, categoryId: 'rent', parentTxnId: 'p1'),
        txn(id: 'x', amount: 5, categoryId: 'food'),
      ];
      final spent = spentByCategory(txns);
      expect(spent['food'], 25); // 20 child + 5 normal — parent not counted
      expect(spent['rent'], 10);
      expect(spent[''], isNull);
      expect(monthTotals(txns).expense, 35); // 30 (as children) + 5
    });

    test('without children the same txn counts normally', () {
      expect(spentByCategory([txn(id: 'p1', amount: 30)])[''], 30);
    });
  });

  group('rolloverCarry', () {
    test('positive leftover carries, overspend does not go negative', () {
      expect(rolloverCarry(prevBudget: 100, prevSpent: 40), 60);
      expect(rolloverCarry(prevBudget: 100, prevSpent: 120), 0);
      expect(rolloverCarry(prevBudget: 0, prevSpent: 0), 0);
    });
  });

  group('detectRecurring', () {
    List<Txn> monthly(String merchant, double amount) => [
          for (var m = 3; m <= 7; m++)
            txn(
                id: '$merchant$m',
                amount: amount,
                merchant: merchant,
                date: DateTime(2026, m, 14)),
        ];

    test('finds a monthly subscription and predicts next due', () {
      final items = detectRecurring(monthly('Netflix', 15.49));
      expect(items, hasLength(1));
      expect(items.first.cadence, Cadence.monthly);
      expect(items.first.amount, 15.49);
      expect(items.first.nextDue, DateTime(2026, 8, 14));
      expect(items.first.monthlyCost, closeTo(15.49, 0.001));
    });

    test('finds a weekly charge', () {
      final items = detectRecurring([
        for (var i = 0; i < 4; i++)
          txn(
              id: 'w$i',
              amount: 6.5,
              merchant: 'Blue Bottle',
              date: DateTime(2026, 7, 1 + 7 * i)),
      ]);
      expect(items.single.cadence, Cadence.weekly);
      expect(items.single.monthlyCost, closeTo(6.5 * 52 / 12, 0.01));
    });

    test('ignores <3 occurrences, irregular gaps, unstable amounts', () {
      final few = [
        txn(id: 'a1', amount: 9, merchant: 'X', date: DateTime(2026, 6, 1)),
        txn(id: 'a2', amount: 9, merchant: 'X', date: DateTime(2026, 7, 1)),
      ];
      final irregular = [
        txn(id: 'b1', amount: 9, merchant: 'Y', date: DateTime(2026, 5, 1)),
        txn(id: 'b2', amount: 9, merchant: 'Y', date: DateTime(2026, 5, 11)),
        txn(id: 'b3', amount: 9, merchant: 'Y', date: DateTime(2026, 6, 30)),
      ];
      final unstable = [
        txn(id: 'c1', amount: 5, merchant: 'Z', date: DateTime(2026, 5, 1)),
        txn(id: 'c2', amount: 80, merchant: 'Z', date: DateTime(2026, 6, 1)),
        txn(id: 'c3', amount: 200, merchant: 'Z', date: DateTime(2026, 7, 1)),
      ];
      expect(detectRecurring([...few, ...irregular, ...unstable]), isEmpty);
    });

    test('income and split children are excluded', () {
      final items = detectRecurring([
        for (var m = 3; m <= 7; m++)
          txn(
              id: 'pay$m',
              amount: -2450,
              merchant: 'Payroll',
              date: DateTime(2026, m, 15)),
        for (var m = 3; m <= 7; m++)
          txn(
              id: 'ch$m',
              amount: 12,
              merchant: 'Split Co',
              parentTxnId: 'p$m',
              date: DateTime(2026, m, 10)),
      ]);
      expect(items, isEmpty);
    });

    test('totalMonthlyCost sums normalized costs', () {
      final items = detectRecurring([
        ...monthly('Netflix', 15.49),
        ...monthly('Spotify', 11.99),
      ]);
      expect(totalMonthlyCost(items), closeTo(27.48, 0.001));
    });
  });

  group('budgetProgress / budgetStatus', () {
    test('clamps to [0,1]', () {
      expect(budgetProgress(50, 100), 0.5);
      expect(budgetProgress(150, 100), 1);
      expect(budgetProgress(0, 100), 0);
    });

    test('zero budget: any spend = fully used + over', () {
      expect(budgetProgress(1, 0), 1);
      expect(budgetStatus(1, 0), BudgetStatus.over);
      expect(budgetStatus(0, 0), BudgetStatus.ok);
    });

    test('status thresholds: warn >= 80%, over > 100%', () {
      expect(budgetStatus(79, 100), BudgetStatus.ok);
      expect(budgetStatus(80, 100), BudgetStatus.warning);
      expect(budgetStatus(100, 100), BudgetStatus.warning);
      expect(budgetStatus(100.01, 100), BudgetStatus.over);
    });
  });

  group('transactionsToCsv', () {
    test('escapes commas and quotes, keeps sign', () {
      final csv = transactionsToCsv(
        [
          txn(
              amount: -12.5,
              merchant: 'Cafe "Mơ", Q1',
              description: 'trà sữa',
              categoryId: 'food'),
        ],
        accountNames: {'acc1': 'Vietcombank'},
        categoryNames: {'food': 'Ăn uống'},
      );
      final lines = csv.trim().split('\n');
      expect(lines.first,
          'date,amount,currency,account,category,merchant,description,pending');
      expect(lines[1], contains('-12.50'));
      expect(lines[1], contains('"Cafe ""Mơ"", Q1"'));
      expect(lines[1], contains('Vietcombank'));
      expect(lines[1], contains('Ăn uống'));
    });

    test('neutralizes spreadsheet formula injection in text cells', () {
      final csv = transactionsToCsv(
        [txn(amount: 5, merchant: '=HYPERLINK("http://evil")', description: '@cmd')],
        accountNames: {'acc1': 'A'},
        categoryNames: {},
      );
      final line = csv.trim().split('\n')[1];
      expect(line, contains("'=HYPERLINK"));
      expect(line, contains("'@cmd"));
      // Amount column keeps its numeric sign untouched.
      expect(line, startsWith('2026-08-15,5.00'));
    });
  });

  group('model parsing', () {
    test('Txn.fromJson maps Supabase row', () {
      final t = Txn.fromJson({
        'id': 't1',
        'account_id': 'a1',
        'plaid_transaction_id': 'p1',
        'amount': 42.13,
        'currency': 'USD',
        'date': '2026-08-01',
        'merchant_name': 'Target',
        'description': null,
        'category_id': null,
        'is_pending': true,
      });
      expect(t.isManual, false);
      expect(t.isExpense, true);
      expect(t.title, 'Target');
      expect(t.date, DateTime(2026, 8, 1));
      expect(t.isPending, true);
    });

    test('Account.fromJson: manual when plaid_item_id null', () {
      final a = Account.fromJson({
        'id': 'a1',
        'plaid_item_id': null,
        'name': 'Cash',
        'type': 'cash',
        'currency': 'USD',
        'current_balance': 100,
        'balance_updated_at': null,
      });
      expect(a.isManual, true);
      expect(a.currentBalance, 100);
    });
  });
}
