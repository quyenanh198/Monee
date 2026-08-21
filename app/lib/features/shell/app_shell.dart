import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/repositories.dart';
import '../settings/settings_screen.dart' show themeModeProvider;

const _tabs = [
  (path: '/dashboard', icon: LucideIcons.layoutDashboard, label: 'Tổng quan'),
  (path: '/transactions', icon: LucideIcons.arrowLeftRight, label: 'Giao dịch'),
  (path: '/budgets', icon: LucideIcons.piggyBank, label: 'Ngân sách'),
  (path: '/reports', icon: LucideIcons.barChart3, label: 'Báo cáo'),
  (path: '/settings', icon: LucideIcons.settings, label: 'Cài đặt'),
];

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  int _index(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    final i = _tabs.indexWhere((t) => loc.startsWith(t.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the live-refresh Realtime channel alive for the whole session.
    ref.watch(realtimeRefreshProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final index = _index(context);

    if (wide) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(_tabs[i].path),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Column(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: Center(
                      child: Text('M',
                          style: TextStyle(
                            color: dark ? const Color(0xFF0F172A) : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          )),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Monee',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      tooltip: dark ? 'Chuyển giao diện sáng' : 'Chuyển giao diện tối',
                      icon: Icon(dark ? LucideIcons.sun : LucideIcons.moon),
                      onPressed: () => ref
                          .read(themeModeProvider.notifier)
                          .set(dark ? ThemeMode.light : ThemeMode.dark),
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(
                      icon: Icon(t.icon), label: Text(t.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
