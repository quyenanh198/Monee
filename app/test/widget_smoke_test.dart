import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monee/core/fx.dart';
import 'package:monee/core/theme.dart';
import 'package:monee/data/repositories.dart';
import 'package:monee/features/dashboard/dashboard_screen.dart';
import 'package:monee/features/reports/reports_screen.dart';
import 'package:monee/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Layout smoke tests: pump the redesigned screens with representative data
// so a rendering exception (overflow crash, null deref in build) fails CI
// instead of white-screening production.

Account _acc(String id, String name, double bal, {String? plaid}) => Account(
      id: id,
      plaidItemId: plaid,
      name: name,
      type: 'checking',
      currency: 'USD',
      currentBalance: bal,
      balanceUpdatedAt: DateTime(2026, 8, 20),
    );

Txn _txn(String id, double amount, DateTime date, {String? cat}) => Txn(
      id: id,
      accountId: 'a1',
      plaidTransactionId: null,
      amount: amount,
      currency: 'USD',
      date: date,
      merchantName: amount > 0 ? 'Coffee Shop' : 'Salary Inc',
      description: null,
      categoryId: cat,
      isPending: false,
    );

List<Override> _overrides(List<Txn> txns) => [
      currentUserIdProvider.overrideWithValue('u1'),
      accountsProvider.overrideWith((ref) async =>
          [_acc('a1', 'Checking', 3246.80), _acc('a2', 'Savings', 7812.45, plaid: 'p1')]),
      categoriesProvider.overrideWith((ref) async => const [
            Category(id: 'c1', userId: null, name: 'Ăn uống', icon: 'utensils'),
            Category(id: 'c2', userId: null, name: 'Nhà ở', icon: 'home'),
          ]),
      transactionsProvider.overrideWith((ref) async => txns),
      sixMonthTxnsProvider.overrideWith((ref) async => txns),
      monthTxnsProvider.overrideWith((ref, m) async => txns
          .where((t) => t.date.year == m.year && t.date.month == m.month)
          .toList()),
      recentTxnsProvider.overrideWith((ref) => Stream.value(txns.take(5).toList())),
      snapshotsProvider.overrideWith((ref) async => [
            BalanceSnapshot(date: DateTime(2026, 8, 1), total: 10500),
            BalanceSnapshot(date: DateTime(2026, 8, 20), total: 11059.25),
          ]),
      vndRateProvider.overrideWith((ref) async => null),
    ];

Widget _app(Widget child, List<Txn> txns) => ProviderScope(
      overrides: _overrides(txns),
      child: MaterialApp(theme: moneeTheme(Brightness.light), home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final now = DateTime.now();
  final txns = [
    for (var i = 0; i < 12; i++)
      _txn('t$i', i.isEven ? 45.5 + i : -1200.0, now.subtract(Duration(days: i * 4)),
          cat: i % 3 == 0 ? 'c1' : (i % 3 == 1 ? 'c2' : null)),
  ];

  testWidgets('dashboard renders with data', (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_app(const DashboardScreen(), txns));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Tổng số dư'), findsOneWidget);
    expect(find.text('Giao dịch gần đây'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard renders on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(400, 880);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_app(const DashboardScreen(), txns));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports renders with data', (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_app(const ReportsScreen(), txns));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Danh mục hàng đầu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
