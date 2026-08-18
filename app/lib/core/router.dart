import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/accounts/accounts_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/recurring/recurring_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/rules/rules_screen.dart';
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

/// Single app-lifetime router. Built once — rebuilding MoneeApp (e.g. on a
/// theme change) must NOT create a new GoRouter, or navigation state resets
/// to the initial location and the auth listener leaks.
final routerProvider = Provider<GoRouter>((_) => buildRouter());

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
            builder: (_, __) => const TransactionsScreen(),
            routes: [
              GoRoute(
                  path: 'recurring',
                  builder: (_, __) => const RecurringScreen()),
            ],
          ),
          GoRoute(
            path: '/budgets',
            builder: (_, __) => const BudgetsScreen(),
            routes: [
              GoRoute(path: 'goals', builder: (_, __) => const GoalsScreen()),
            ],
          ),
          GoRoute(
              path: '/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'rules', builder: (_, __) => const RulesScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}
