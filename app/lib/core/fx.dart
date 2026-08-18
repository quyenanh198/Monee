/// USD→VND display conversion. Rate comes from the fx-rate Edge Function
/// (free upstream, no key) and is cached locally for 12 hours.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _showVndKey = 'monee_show_vnd';
const _rateKey = 'monee_vnd_rate';
const _rateAtKey = 'monee_vnd_rate_at';

final showVndProvider =
    StateNotifierProvider<ShowVndNotifier, bool>((_) => ShowVndNotifier());

class ShowVndNotifier extends StateNotifier<bool> {
  ShowVndNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_showVndKey) ?? false;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showVndKey, value);
  }
}

/// null = rate not available (offline and no cache yet).
final vndRateProvider = FutureProvider<double?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getDouble(_rateKey);
  final cachedAt = prefs.getInt(_rateAtKey) ?? 0;
  final fresh = DateTime.now().millisecondsSinceEpoch - cachedAt <
      const Duration(hours: 12).inMilliseconds;
  if (cached != null && fresh) return cached;

  try {
    final res = await Supabase.instance.client.functions.invoke('fx-rate');
    final data = res.data as Map<String, dynamic>;
    final rate = (data['rate'] as num).toDouble();
    await prefs.setDouble(_rateKey, rate);
    await prefs.setInt(_rateAtKey, DateTime.now().millisecondsSinceEpoch);
    return rate;
  } catch (_) {
    return cached; // stale cache beats nothing
  }
});

/// "₫32.500.000" — no decimals, Vietnamese grouping.
String vnd(num usd, double rate) {
  final f = NumberFormat.currency(locale: 'vi', symbol: '₫', decimalDigits: 0);
  return f.format(usd * rate);
}
