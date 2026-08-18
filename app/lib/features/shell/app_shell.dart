import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _tabs = [
  (path: '/dashboard', icon: LucideIcons.layoutDashboard, label: 'Tổng quan'),
  (path: '/transactions', icon: LucideIcons.arrowLeftRight, label: 'Giao dịch'),
  (path: '/budgets', icon: LucideIcons.piggyBank, label: 'Ngân sách'),
  (path: '/reports', icon: LucideIcons.barChart3, label: 'Báo cáo'),
  (path: '/settings', icon: LucideIcons.settings, label: 'Cài đặt'),
];

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  int _index(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    final i = _tabs.indexWhere((t) => loc.startsWith(t.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final index = _index(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(_tabs[i].path),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(
                      icon: Icon(t.icon), label: Text(t.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
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
