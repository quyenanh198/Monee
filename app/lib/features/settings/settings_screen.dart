import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/fx.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import 'csv_export.dart';

const _themeKey = 'monee_theme_mode';

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((_) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_themeKey);
    if (v == 'dark') state = ThemeMode.dark;
    if (v == 'system') state = ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final email =
        ref.watch(supabaseProvider).auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(LucideIcons.moon),
                title: const Text('Giao diện'),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.light, label: Text('Sáng')),
                    ButtonSegment(
                        value: ThemeMode.dark, label: Text('Tối')),
                    ButtonSegment(
                        value: ThemeMode.system, label: Text('Hệ thống')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) =>
                      ref.read(themeModeProvider.notifier).set(s.first),
                ),
              ),
              _VndTile(),
              ListTile(
                leading: const Icon(LucideIcons.wand2),
                title: const Text('Rules phân loại tự động'),
                subtitle: const Text(
                    'Tự gán danh mục cho giao dịch mới theo merchant/mô tả'),
                onTap: () => context.go('/settings/rules'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.fileUp),
                title: const Text('Nhập CSV giao dịch'),
                subtitle: const Text('Dán export từ ngân hàng / app cũ'),
                onTap: () => context.go('/settings/import'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.fileDown),
                title: const Text('Xuất CSV giao dịch'),
                subtitle: const Text('Sao chép toàn bộ giao dịch vào clipboard'),
                onTap: () => _exportCsv(context, ref),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(LucideIcons.logOut),
              title: const Text('Đăng xuất'),
              subtitle: Text(email),
              onTap: () => ref.read(supabaseProvider).auth.signOut(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(supabaseProvider);
    // Concurrent, and paginated past PostgREST's 1000-row cap.
    final results = await Future.wait<dynamic>([
      fetchAllTxns(db),
      db.from('accounts').select('id, name'),
      db.from('categories').select('id, name'),
    ]);
    final txns = results[0] as List<Txn>;
    final accRows = results[1] as List<Map<String, dynamic>>;
    final catRows = results[2] as List<Map<String, dynamic>>;

    final csv = transactionsToCsv(
      txns,
      accountNames: {
        for (final r in accRows) r['id'] as String: r['name'] as String
      },
      categoryNames: {
        for (final r in catRows) r['id'] as String: r['name'] as String
      },
    );
    await Clipboard.setData(ClipboardData(text: csv));
    messenger.showSnackBar(SnackBar(
        content: Text('Đã sao chép ${txns.length} giao dịch (CSV)')));
  }
}

/// VND display-conversion toggle + current reference rate.
class _VndTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(showVndProvider);
    final rate = ref.watch(vndRateProvider).valueOrNull;
    return SwitchListTile(
      secondary: const Icon(LucideIcons.banknote),
      title: const Text('Quy đổi sang VND'),
      subtitle: Text(rate == null
          ? 'Hiện giá trị ≈ ₫ cạnh tổng số dư'
          : '1 USD ≈ ${vnd(1, rate)} (tham khảo, cập nhật hằng ngày)'),
      value: show,
      onChanged: (v) => ref.read(showVndProvider.notifier).set(v),
    );
  }
}
