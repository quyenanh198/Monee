import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/accounts/accounts_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/transactions/transactions_screen.dart';

/// Re-notifies the router when Supabase auth state changes.
class _AuthRefresh extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;
  _AuthRefresh() {
    _sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: _AuthRefresh(),
    redirect: (context, state) {
      final signedIn = Supabase.instance.client.auth.currentUser != null;
      final onLogin = state.uri.path == '/login';
      if (!signedIn && !onLogin) return '/login';
      if (signedIn && onLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
            routes: [
              GoRoute(
                  path: 'accounts',
                  builder: (_, __) => const AccountsScreen()),
            ],
          ),
          GoRoute(
              path: '/transactions',
              builder: (_, __) => const TransactionsScreen()),
          GoRoute(
              path: '/budgets', builder: (_, __) => const BudgetsScreen()),
          GoRoute(
              path: '/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(
              path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),
    ],
  );
}
