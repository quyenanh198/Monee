import 'package:flutter_test/flutter_test.dart';
import 'package:monee/features/budgets/budget_logic.dart';
import 'package:monee/features/recurring/recurring_logic.dart';
import 'package:monee/features/settings/csv_export.dart';
import 'package:monee/features/settings/csv_import.dart';
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

    test('includeIncome detects recurring income with negative amount', () {
      final items = detectRecurring(
        [
          for (var m = 3; m <= 7; m++)
            txn(
                id: 'pay$m',
                amount: -2450,
                merchant: 'Payroll',
                date: DateTime(2026, m, 15)),
        ],
        includeIncome: true,
      );
      expect(items.single.amount, -2450);
      expect(items.single.cadence, Cadence.monthly);
    });
  });

  group('forecastBalance', () {
    test('replays charges and income as step events', () {
      // lastDate 2026-08-10 → nextDue 2026-09-10 (inside 30-day window)
      final rent = RecurringItem(
          name: 'Rent',
          categoryId: null,
          amount: 800,
          cadence: Cadence.monthly,
          lastDate: DateTime(2026, 8, 10),
          occurrences: 3);
      final pay = RecurringItem(
          name: 'Payroll',
          categoryId: null,
          amount: -1000,
          cadence: Cadence.monthly,
          lastDate: DateTime(2026, 8, 15),
          occurrences: 3);

      final points = forecastBalance(
        startBalance: 500,
        items: [rent, pay],
        from: DateTime(2026, 8, 18),
        days: 30,
      );
      expect(points.first.balance, 500);
      final afterRent =
          points.firstWhere((p) => p.date == DateTime(2026, 9, 10));
      expect(afterRent.balance, -300); // 500 - 800
      final afterPay =
          points.firstWhere((p) => p.date == DateTime(2026, 9, 15));
      expect(afterPay.balance, 700); // -300 + 1000
      expect(points.last.balance, 700);
      expect(minForecastBalance(points), -300);
    });

    test('overdue item is advanced into the window, not looped', () {
      final old = RecurringItem(
          name: 'Gym',
          categoryId: null,
          amount: 50,
          cadence: Cadence.monthly,
          lastDate: DateTime(2025, 1, 5),
          occurrences: 5);
      final points = forecastBalance(
        startBalance: 100,
        items: [old],
        from: DateTime(2026, 8, 18),
        days: 30,
      );
      // exactly one charge (2026-09-05) falls in the window
      expect(points.last.balance, 50);
    });
  });

  group('csv import', () {
    test('parses quoted cells, CRLF and auto delimiter', () {
      final rows = parseCsv(
          'Date,Amount,Description\r\n'
          '2026-08-01,-12.50,"Cafe ""Mơ"", Q1"\r\n'
          '08/15/2026,"\$1,200.00",Rent\r\n');
      expect(rows, hasLength(3));
      expect(rows[1][2], 'Cafe "Mơ", Q1');
      expect(rows[2][1], r'$1,200.00');

      final semi = parseCsv('a;b;c\n1;2;3\n');
      expect(semi[1], ['1', '2', '3']);
    });

    test('autoMap finds columns by header names', () {
      final m = autoMap(['Posting Date', 'Description', 'Amount']);
      expect(m, isNotNull);
      expect(m!.dateCol, 0);
      expect(m.amountCol, 2);
      expect(m.descCol, 1);
      expect(autoMap(['foo', 'bar']), isNull);
    });

    test('flexible dates: ISO, MM/dd/yyyy, dd/MM/yyyy disambiguated', () {
      expect(parseFlexibleDate('2026-08-01'), DateTime(2026, 8, 1));
      expect(parseFlexibleDate('08/15/2026'), DateTime(2026, 8, 15));
      expect(parseFlexibleDate('15/08/2026'), DateTime(2026, 8, 15));
      expect(parseFlexibleDate('not a date'), isNull);
    });

    test('amounts: currency symbols, thousands, parentheses negative', () {
      expect(parseAmount(r'$1,234.56'), 1234.56);
      expect(parseAmount('(12.50)'), -12.50);
      expect(parseAmount('-3'), -3);
      expect(parseAmount('abc'), isNull);
    });

    test('mapCsv skips bad rows and can invert sign', () {
      final rows = [
        ['2026-08-01', '-12.50', 'Coffee'],
        ['bad date', '5', 'x'],
        ['2026-08-02', '100', 'Salary refund'],
      ];
      final normal = mapCsv(rows,
          const CsvMapping(dateCol: 0, amountCol: 1, descCol: 2));
      expect(normal.txns, hasLength(2));
      expect(normal.skipped, 1);
      expect(normal.txns.first.amount, -12.50);

      final inverted = mapCsv(rows,
          const CsvMapping(
              dateCol: 0, amountCol: 1, descCol: 2, invertSign: true));
      // bank convention (negative = out) flipped to app convention
      expect(inverted.txns.first.amount, 12.50);
      expect(inverted.txns.first.description, 'Coffee');
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
