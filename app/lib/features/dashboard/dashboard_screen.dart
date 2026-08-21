import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/fx.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../budgets/budget_logic.dart';
import '../recurring/recurring_logic.dart';
import '../recurring/recurring_providers.dart';
import '../transactions/quick_add_sheet.dart';
import '../transactions/transactions_screen.dart' show showTxnForm;

Widget _legendDot(Color color, String label) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 11) return 'Chào buổi sáng';
  if (h < 14) return 'Chào buổi trưa';
  if (h < 18) return 'Chào buổi chiều';
  return 'Chào buổi tối';
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final month = monthStart(DateTime.now());
    final monthTxns = ref.watch(monthTxnsProvider(month));
    final lastMonthTxns = ref.watch(monthTxnsProvider(addMonths(month, -1)));
    final recent = ref.watch(recentTxnsProvider);
    final catNames = ref.watch(categoryNamesProvider);
    final cats = ref.watch(categoriesProvider).valueOrNull ?? [];
    final catIcons = {for (final c in cats) c.id: c.icon};
    final accList = accounts.valueOrNull ?? [];
    final sixMonth = ref.watch(sixMonthTxnsProvider).valueOrNull ?? [];

    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    return Scaffold(
      // Wide screens already have "+ Thêm" in the top bar.
      floatingActionButton: wide
          ? null
          : FloatingActionButton(
              tooltip: 'Thêm giao dịch nhanh',
              onPressed: () => showQuickAddSheet(context, ref),
              child: const Icon(LucideIcons.plus),
            ),
      body: RefreshIndicator(
        onRefresh: () async => refreshData(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_greeting()} 👋',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Đây là tổng quan tài chính của bạn.',
                        style: TextStyle(color: mutedColor(context))),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Tài khoản',
                icon: const Icon(LucideIcons.landmark),
                onPressed: () => context.go('/dashboard/accounts'),
              ),
              IconButton(
                tooltip: 'Đồng bộ ngân hàng',
                icon: const Icon(LucideIcons.refreshCw),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(plaidServiceProvider).syncNow();
                    refreshData(ref);
                    messenger.showSnackBar(
                        const SnackBar(content: Text('Đồng bộ xong')));
                  } catch (e) {
                    messenger
                        .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                  }
                },
              ),
            ]),
            const SizedBox(height: 16),
            _BalanceHero(
              accounts: accList,
              snapshots: ref.watch(snapshotsProvider).valueOrNull ?? [],
              showVnd: ref.watch(showVndProvider),
              vndRate: ref.watch(vndRateProvider).valueOrNull,
            ),
            if (accList.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AccountsStrip(accounts: accList),
            ],
            const SizedBox(height: 16),
            // Responsive: two columns on wide screens, stacked on narrow.
            LayoutBuilder(builder: (context, c) {
              final cashFlow = _CashFlowCard(txns: sixMonth);
              final donut =
                  _SpendDonut(monthTxns: monthTxns, catNames: catNames);
              final bills =
                  _UpcomingBills(items: ref.watch(recurringItemsProvider));
              final insight = _InsightCard(
                thisMonth: monthTxns.valueOrNull ?? [],
                lastMonth: lastMonthTxns.valueOrNull ?? [],
              );
              if (c.maxWidth >= 960) {
                return Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: cashFlow),
                    const SizedBox(width: 16),
                    Expanded(child: donut),
                  ]),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: bills),
                    const SizedBox(width: 16),
                    Expanded(child: insight),
                  ]),
                ]);
              }
              return Column(children: [
                cashFlow,
                const SizedBox(height: 16),
                donut,
                bills,
                insight,
              ]);
            }),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text('Giao dịch gần đây',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () => context.go('/transactions'),
                child: const Text('Xem tất cả'),
              ),
            ]),
            const SizedBox(height: 4),
            AsyncBody(
              value: recent,
              builder: (txns) {
                if (txns.isEmpty) {
                  return const EmptyState(
                      'Chưa có giao dịch. Liên kết ngân hàng hoặc thêm tay.');
                }
                final wide =
                    MediaQuery.sizeOf(context).width >= kWideBreakpoint;
                if (wide) {
                  return _TxnTable(
                    txns: txns,
                    catNames: catNames,
                    accountNames: {for (final a in accList) a.id: a.name},
                    onTap: (t) => showTxnForm(context, ref,
                        accounts: accList, cats: cats, existing: t),
                  );
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final t in txns)
                      TxnTile(
                        txn: t,
                        categoryName: catNames[t.categoryId],
                        categoryIconName: catIcons[t.categoryId],
                        onTap: () => showTxnForm(context, ref,
                            accounts: accList, cats: cats, existing: t),
                      ),
                  ]),
                );
              },
            ),
            const SizedBox(height: 80), // FAB clearance
          ],
        ),
      ),
    );
  }
}

/// Hidden-balance toggle (the "eye" on the hero card).
final hideBalanceProvider = StateProvider<bool>((_) => false);

/// Snapshot window for the hero delta badge: 7, 30, or 0 = all.
final _heroPeriodProvider = StateProvider<int>((_) => 30);

/// Signature gradient hero on every screen size (per the sample design):
/// total balance, hide/show eye, period selector for the change badge.
class _BalanceHero extends ConsumerWidget {
  final List<Account> accounts;
  final List<BalanceSnapshot> snapshots;
  final bool showVnd;
  final double? vndRate;
  const _BalanceHero(
      {required this.accounts,
      required this.snapshots,
      required this.showVnd,
      required this.vndRate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = accounts
        .where((a) => a.currency == 'USD')
        .fold(0.0, (s, a) => s + a.currentBalance);
    final hasForeign = accounts.any((a) => a.currency != 'USD');
    final hidden = ref.watch(hideBalanceProvider);
    final period = ref.watch(_heroPeriodProvider);

    // Change over the selected snapshot window (daily cron snapshots).
    final cutoff = DateTime.now().subtract(Duration(days: period));
    final win = period == 0
        ? snapshots
        : snapshots.where((s) => !s.date.isBefore(cutoff)).toList();
    double? pct;
    double? delta;
    if (win.length >= 2 && win.first.total != 0) {
      delta = win.last.total - win.first.total;
      pct = delta / win.first.total.abs() * 100;
    }

    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: moneeGradient,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Flexible(
            child: Text('Tổng số dư',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: hidden ? 'Hiện số dư' : 'Ẩn số dư',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(hidden ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 16, color: Colors.white70),
            onPressed: () =>
                ref.read(hideBalanceProvider.notifier).update((v) => !v),
          ),
          const Spacer(),
          Theme(
            data: Theme.of(context).copyWith(canvasColor: null),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: period,
                dropdownColor: MoneeColors.primary,
                iconEnabledColor: Colors.white70,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 ngày')),
                  DropdownMenuItem(value: 30, child: Text('30 ngày')),
                  DropdownMenuItem(value: 0, child: Text('Tất cả')),
                ],
                onChanged: (v) => ref
                    .read(_heroPeriodProvider.notifier)
                    .state = v ?? 30,
              ),
            ),
          ),
          if (!wide) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => context.go('/dashboard/accounts'),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                child: const Icon(LucideIcons.wallet,
                    size: 18, color: Colors.white),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Text(hidden ? '••••••' : money(total),
            style: moneyStyle(context,
                size: wide ? 38 : 34,
                color: Colors.white,
                weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (pct != null && !hidden)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      delta! >= 0
                          ? LucideIcons.trendingUp
                          : LucideIcons.trendingDown,
                      size: 12,
                      color: Colors.white),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${money(delta.abs())} (${pct.abs().toStringAsFixed(1)}%) '
                      '${period == 0 ? 'từ đầu' : 'trong $period ngày'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12.5),
                    ),
                  ),
                ]),
              ),
            ),
          if (showVnd && vndRate != null && !hidden)
            Text('≈ ${vnd(total, vndRate!)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          if (hasForeign)
            const Text('chưa gồm tài khoản ngoại tệ',
                style: TextStyle(color: Colors.white70, fontSize: 12.5)),
        ]),
      ]),
    );
  }
}

/// Desktop-style transaction table: Ngày | Mô tả | Danh mục | Tài khoản | Số tiền.
class _TxnTable extends StatelessWidget {
  final List<Txn> txns;
  final Map<String, String> catNames;
  final Map<String, String> accountNames;
  final void Function(Txn) onTap;
  const _TxnTable(
      {required this.txns,
      required this.catNames,
      required this.accountNames,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final headStyle = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: mutedColor(context));
    final border = Theme.of(context).brightness == Brightness.dark
        ? MoneeColors.darkBorder
        : MoneeColors.lightBorder;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(children: [
            SizedBox(width: 92, child: Text('Ngày', style: headStyle)),
            Expanded(flex: 3, child: Text('Mô tả', style: headStyle)),
            Expanded(flex: 2, child: Text('Danh mục', style: headStyle)),
            Expanded(flex: 2, child: Text('Tài khoản', style: headStyle)),
            SizedBox(
              width: 110,
              child: Text('Số tiền',
                  textAlign: TextAlign.right, style: headStyle),
            ),
          ]),
        ),
        for (final t in txns) ...[
          Container(height: 1, color: border),
          InkWell(
            onTap: () => onTap(t),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                SizedBox(
                  width: 92,
                  child: Text(shortDate(t.date),
                      style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5)),
                ),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CategoryChip(
                        categoryId: t.categoryId,
                        name: catNames[t.categoryId]),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(accountNames[t.accountId] ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: mutedColor(context))),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    money(t.amount, currency: t.currency, signed: true),
                    textAlign: TextAlign.right,
                    style: moneyStyle(context,
                        size: 13.5,
                        color: t.isExpense
                            ? MoneeColors.destructive
                            : MoneeColors.accent),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Horizontal strip of account cards.
class _AccountsStrip extends ConsumerWidget {
  final List<Account> accounts;
  const _AccountsStrip({required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    final hidden = ref.watch(hideBalanceProvider);
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length,
        separatorBuilder: (_, i) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final a = accounts[i];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.go('/dashboard/accounts'),
              child: Container(
              width: 168,
              padding: const EdgeInsets.all(12),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: primary.withValues(alpha: 0.10),
                    ),
                    child: Icon(
                        a.isManual ? LucideIcons.wallet : LucideIcons.landmark,
                        size: 15,
                        color: primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const Spacer(),
                Text(
                    hidden
                        ? '••••'
                        : money(a.currentBalance, currency: a.currency),
                    style: moneyStyle(context, size: 16)),
              ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cash flow with a 7/30-day selector (spec): income vs expense lines
/// (rolling sum so single spikes still read as a curve) + Thu/Chi/Ròng.
class _CashFlowCard extends StatefulWidget {
  final List<Txn> txns;
  const _CashFlowCard({required this.txns});

  @override
  State<_CashFlowCard> createState() => _CashFlowCardState();
}

class _CashFlowCardState extends State<_CashFlowCard> {
  int days = 30;

  @override
  Widget build(BuildContext context) {
    final txns = widget.txns;
    final today = DateTime.now();
    final from = today.subtract(Duration(days: days - 1));
    final window = effectiveTxns(txns)
        .where((t) =>
            t.currency == 'USD' &&
            !t.date.isBefore(DateTime(from.year, from.month, from.day)))
        .toList();
    if (window.isEmpty) return const SizedBox.shrink();

    final inDay = List<double>.filled(days, 0);
    final outDay = List<double>.filled(days, 0);
    var income = 0.0, expense = 0.0;
    for (final t in window) {
      final i = t.date
          .difference(DateTime(from.year, from.month, from.day))
          .inDays;
      if (i < 0 || i >= days) continue;
      if (t.amount > 0) {
        outDay[i] += t.amount;
        expense += t.amount;
      } else {
        inDay[i] += -t.amount;
        income += -t.amount;
      }
    }
    final smooth = days >= 30 ? 6 : 2; // rolling window scales with range
    List<FlSpot> rolling(List<double> d) => [
          for (var i = 0; i < days; i++)
            FlSpot(
              i.toDouble(),
              [
                for (var j = i - smooth < 0 ? 0 : i - smooth; j <= i; j++) d[j]
              ].fold(0.0, (s, v) => s + v),
            ),
        ];
    final net = income - expense;

    LineChartBarData line(List<FlSpot> spots, Color color) =>
        LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 2,
          isCurved: true,
          curveSmoothness: 0.3,
          preventCurveOverShooting: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.14),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Dòng tiền',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            _legendDot(MoneeColors.accent, 'Thu'),
            const SizedBox(width: 12),
            _legendDot(MoneeColors.destructive, 'Chi'),
            const SizedBox(width: 12),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              segments: const [
                ButtonSegment(value: 7, label: Text('7d')),
                ButtonSegment(value: 30, label: Text('30d')),
              ],
              selected: {days},
              onSelectionChanged: (s) => setState(() => days = s.first),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(
                  leftTitles: AxisTitles(),
                  topTitles: AxisTitles(),
                  rightTitles: AxisTitles(),
                  bottomTitles: AxisTitles(),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                            money(s.y),
                            TextStyle(
                                color: s.bar.color ?? Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12)),
                    ],
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  line(rolling(inDay), MoneeColors.accent),
                  line(rolling(outDay), MoneeColors.destructive),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _flowStat(context, 'Thu', money(income), MoneeColors.accent),
            _divider(context),
            _flowStat(
                context, 'Chi', money(expense), MoneeColors.destructive),
            _divider(context),
            _flowStat(context, 'Ròng', '${net < 0 ? '-' : ''}${money(net.abs())}',
                net >= 0 ? MoneeColors.accent : MoneeColors.destructive),
          ]),
        ]),
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Theme.of(context).brightness == Brightness.dark
            ? MoneeColors.darkBorder
            : MoneeColors.lightBorder,
      );

  Widget _flowStat(
          BuildContext context, String label, String value, Color color) =>
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: mutedColor(context))),
          const SizedBox(height: 2),
          Text(value, style: moneyStyle(context, size: 14.5, color: color)),
        ]),
      );
}

/// Simple rule-based insight: spending vs last month.
class _InsightCard extends StatelessWidget {
  final List<Txn> thisMonth;
  final List<Txn> lastMonth;
  const _InsightCard({required this.thisMonth, required this.lastMonth});

  @override
  Widget build(BuildContext context) {
    final now = monthTotals(thisMonth).expense;
    final prev = monthTotals(lastMonth).expense;
    if (prev <= 0 || now <= 0) return const SizedBox.shrink();
    final pct = ((now - prev) / prev * 100);
    final lower = pct <= 0;
    final color = lower ? MoneeColors.accent : MoneeColors.warning;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(
                  lower ? LucideIcons.trendingDown : LucideIcons.trendingUp,
                  size: 20,
                  color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Insight chi tiêu',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    lower
                        ? 'Bạn đang chi ít hơn ${pct.abs().toStringAsFixed(0)}% so với cùng kỳ tháng trước. Tiếp tục phát huy!'
                        : 'Chi tiêu tháng này đang cao hơn ${pct.abs().toStringAsFixed(0)}% so với tháng trước.',
                    style: TextStyle(
                        fontSize: 13, color: mutedColor(context)),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => context.go('/reports'),
              child: const Text('Chi tiết'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Recurring charges due in the next 14 days.
class _UpcomingBills extends StatelessWidget {
  final List<RecurringItem> items;
  const _UpcomingBills({required this.items});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final horizon = today.add(const Duration(days: 14));
    final due =
        items.where((i) => i.nextDue.isBefore(horizon)).take(4).toList();
    if (due.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Hóa đơn sắp tới',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => context.go('/transactions/recurring'),
                  child: const Text('Tất cả'),
                ),
              ]),
              for (final i in due)
                InkWell(
                  onTap: () => context.go('/transactions/recurring'),
                  child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 8),
                  child: Row(children: [
                    const Icon(LucideIcons.repeat, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(i.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text(shortDate(i.nextDue),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 12),
                    Text(money(i.amount),
                        style: moneyStyle(context, size: 13.5)),
                  ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpendDonut extends ConsumerWidget {
  final AsyncValue<List<Txn>> monthTxns;
  final Map<String, String> catNames;
  const _SpendDonut({required this.monthTxns, required this.catNames});

  /// Tapping a legend item drills into Transactions filtered by that
  /// category for the current month.
  void _drill(BuildContext context, WidgetRef ref, String categoryKey) {
    ref.read(txnFilterProvider.notifier).update((f) => f.copyWith(
          categoryId: () => categoryKey.isEmpty ? null : categoryKey,
          month: () => monthStart(DateTime.now()),
        ));
    context.go('/transactions');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: monthTxns,
      builder: (txns) {
        final spent = spentByCategory(txns);
        if (spent.isEmpty) {
          return const SizedBox.shrink();
        }
        final entries = spent.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final total = entries.fold(0.0, (s, e) => s + e.value);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('Chi tiêu theo danh mục',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: () => context.go('/reports'),
                    child: const Text('Xem báo cáo đầy đủ →'),
                  ),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: Stack(alignment: Alignment.center, children: [
                    PieChart(
                      PieChartData(
                        centerSpaceRadius: 52,
                        sectionsSpace: 2,
                        sections: [
                          for (final e in entries)
                            PieChartSectionData(
                              value: e.value,
                              color: categoryColor(e.key),
                              showTitle: false,
                              radius: 34,
                            ),
                        ],
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(money(total), style: moneyStyle(context, size: 17)),
                      Text('Tổng',
                          style: TextStyle(
                              fontSize: 12, color: mutedColor(context))),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    for (final e in entries.take(6))
                      InkWell(
                        onTap: () => _drill(context, ref, e.key),
                        borderRadius: BorderRadius.circular(6),
                        child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: categoryColor(e.key),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${e.key.isEmpty ? 'Chưa phân loại' : catNames[e.key] ?? '?'} · ${money(e.value)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
