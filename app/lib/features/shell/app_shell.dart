import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../settings/settings_screen.dart' show themeModeProvider;
import '../transactions/quick_add_sheet.dart';

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
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    final index = _index(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(index: index),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(children: [
                const _TopBar(),
                const Divider(height: 1),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: child,
                    ),
                  ),
                ),
              ]),
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

/// Full sidebar (Finovo-style): logo + name, icon+label rows with an active
/// pill, light/dark switch pinned to the bottom.
class _Sidebar extends ConsumerWidget {
  final int index;
  const _Sidebar({required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: 216,
      color: dark ? MoneeColors.darkSurface : Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: primary),
              child: Center(
                child: Text('M',
                    style: TextStyle(
                      color: dark ? const Color(0xFF0F172A) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    )),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Monee',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
        for (var i = 0; i < _tabs.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.go(_tabs[i].path),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: i == index ? primary.withValues(alpha: 0.10) : null,
                ),
                child: Row(children: [
                  Icon(_tabs[i].icon,
                      size: 19,
                      color: i == index ? primary : mutedColor(context)),
                  const SizedBox(width: 12),
                  Text(
                    _tabs[i].label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          i == index ? FontWeight.w600 : FontWeight.w500,
                      color: i == index ? primary : null,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(LucideIcons.sun, size: 16, color: mutedColor(context)),
            const SizedBox(width: 6),
            Switch(
              value: dark,
              onChanged: (v) => ref
                  .read(themeModeProvider.notifier)
                  .set(v ? ThemeMode.dark : ThemeMode.light),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.moon, size: 16, color: mutedColor(context)),
          ]),
        ),
      ]),
    );
  }
}

/// Top bar: global transaction search, primary "+ Thêm" (Quick Add), avatar.
class _TopBar extends ConsumerStatefulWidget {
  const _TopBar();

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _submitSearch(String q) {
    ref.read(txnFilterProvider.notifier).update((f) => f.copyWith(search: q));
    context.go('/transactions');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final email =
        ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    final initials =
        email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();

    return Container(
      color: dark ? MoneeColors.darkSurface : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: TextField(
              controller: search,
              onSubmitted: _submitSearch,
              decoration: InputDecoration(
                hintText: 'Tìm giao dịch…',
                prefixIcon: const Icon(LucideIcons.search, size: 17),
                suffixIcon: IconButton(
                  tooltip: 'Tìm',
                  icon: const Icon(LucideIcons.arrowRight, size: 16),
                  onPressed: () => _submitSearch(search.text),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: () => showQuickAddSheet(context, ref),
          icon: const Icon(LucideIcons.plus, size: 17),
          label: const Text('Thêm'),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<String>(
          tooltip: email,
          offset: const Offset(0, 44),
          onSelected: (v) {
            if (v == 'settings') context.go('/settings');
            if (v == 'logout') ref.read(supabaseProvider).auth.signOut();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
                enabled: false,
                child: Text(email, style: const TextStyle(fontSize: 12.5))),
            const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                    dense: true,
                    leading: Icon(LucideIcons.settings, size: 17),
                    title: Text('Cài đặt'))),
            const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                    dense: true,
                    leading: Icon(LucideIcons.logOut, size: 17),
                    title: Text('Đăng xuất'))),
          ],
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(initials,
                style: TextStyle(
                    color: dark ? const Color(0xFF0F172A) : Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
