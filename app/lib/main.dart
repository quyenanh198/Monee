import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/settings/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(Env.supabaseUrl.isNotEmpty,
      'Thiếu --dart-define=SUPABASE_URL và SUPABASE_ANON_KEY');
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );
  runApp(const ProviderScope(child: MoneeApp()));
}

class MoneeApp extends ConsumerWidget {
  const MoneeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Monee',
      debugShowCheckedModeBanner: false,
      theme: moneeTheme(Brightness.light),
      darkTheme: moneeTheme(Brightness.dark),
      themeMode: mode,
      routerConfig: buildRouter(),
    );
  }
}
