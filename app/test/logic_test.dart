import 'package:flutter_test/flutter_test.dart';
import 'package:monee/features/budgets/budget_logic.dart';
import 'package:monee/features/settings/csv_export.dart';
import 'package:monee/models/models.dart';

Txn txn({
  double amount = 10,
  String? categoryId,
  String accountId = 'acc1',
  DateTime? date,
  String? merchant,
  String? description,
}) =>
    Txn(
      id: 'id',
      accountId: accountId,
      plaidTransactionId: null,
      amount: amount,
      currency: 'USD',
      date: date ?? DateTime(2026, 8, 15),
      merchantName: merchant,
      description: description,
      categoryId: categoryId,
      isPending: false,
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
