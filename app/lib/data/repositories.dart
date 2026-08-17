import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import '../models/models.dart';

final supabaseProvider =
    Provider<SupabaseClient>((_) => Supabase.instance.client);

String _uid(SupabaseClient db) => db.auth.currentUser!.id;

// ------------------------------------------------------------------ accounts

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final db = ref.watch(supabaseProvider);
  final rows = await db.from('accounts').select().order('created_at');
  return rows.map(Account.fromJson).toList();
});

Future<void> createManualAccount(
  SupabaseClient db, {
  required String name,
  required String type,
  required double balance,
}) async {
  await db.from('accounts').insert({
    'user_id': _uid(db),
    'name': name,
    'type': type,
    'current_balance': balance,
    'balance_updated_at': DateTime.now().toIso8601String(),
  });
}

Future<void> deleteAccount(SupabaseClient db, String id) async {
  await db.from('accounts').delete().eq('id', id);
}

// ---------------------------------------------------------------- categories

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final db = ref.watch(supabaseProvider);
  final rows = await db.from('categories').select().order('name');
  return rows.map(Category.fromJson).toList();
});

Future<void> createCategory(SupabaseClient db, String name) async {
  await db
      .from('categories')
      .insert({'user_id': _uid(db), 'name': name, 'icon': 'tag'});
}

// -------------------------------------------------------------- transactions

class TxnFilter {
  final String? accountId;
  final String? categoryId;
  final DateTime? month; // filter to this calendar month
  final String search;
  const TxnFilter(
      {this.accountId, this.categoryId, this.month, this.search = ''});

  TxnFilter copyWith({
    String? Function()? accountId,
    String? Function()? categoryId,
    DateTime? Function()? month,
    String? search,
  }) =>
      TxnFilter(
        accountId: accountId == null ? this.accountId : accountId(),
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        month: month == null ? this.month : month(),
        search: search ?? this.search,
      );
}

final txnFilterProvider = StateProvider<TxnFilter>((_) => const TxnFilter());
final txnPageSizeProvider = StateProvider<int>((_) => 100);

final transactionsProvider = FutureProvider<List<Txn>>((ref) async {
  final db = ref.watch(supabaseProvider);
  final f = ref.watch(txnFilterProvider);
  final limit = ref.watch(txnPageSizeProvider);

  var q = db.from('transactions').select();
  if (f.accountId != null) q = q.eq('account_id', f.accountId!);
  if (f.categoryId != null) q = q.eq('category_id', f.categoryId!);
  if (f.month != null) {
    q = q
        .gte('date', isoDate(monthStart(f.month!)))
        .lt('date', isoDate(addMonths(f.month!, 1)));
  }
  if (f.search.isNotEmpty) {
    q = q.or('merchant_name.ilike.%${f.search}%,description.ilike.%${f.search}%');
  }
  final rows = await q.order('date', ascending: false).limit(limit);
  return rows.map(Txn.fromJson).toList();
});

/// Realtime stream of the 10 most recent transactions (dashboard).
final recentTxnsProvider = StreamProvider<List<Txn>>((ref) {
  final db = ref.watch(supabaseProvider);
  return db
      .from('transactions')
      .stream(primaryKey: ['id'])
      .eq('user_id', _uid(db))
      .order('date')
      .limit(10)
      .map((rows) => rows.map(Txn.fromJson).toList());
});

/// All transactions in one calendar month (dashboard donut, budgets).
final monthTxnsProvider =
    FutureProvider.family<List<Txn>, DateTime>((ref, month) async {
  final db = ref.watch(supabaseProvider);
  final rows = await db
      .from('transactions')
      .select()
      .gte('date', isoDate(monthStart(month)))
      .lt('date', isoDate(addMonths(month, 1)));
  return rows.map(Txn.fromJson).toList();
});

Future<void> upsertManualTxn(
  SupabaseClient db, {
  String? id,
  required String accountId,
  required double amount,
  required DateTime date,
  String? description,
  String? categoryId,
}) async {
  final row = {
    'user_id': _uid(db),
    'account_id': accountId,
    'amount': amount,
    'date': isoDate(date),
    'description': description,
    'category_id': categoryId,
  };
  if (id == null) {
    await db.from('transactions').insert(row);
  } else {
    await db.from('transactions').update(row).eq('id', id);
  }
}

Future<void> setTxnCategory(
    SupabaseClient db, String txnId, String? categoryId) async {
  await db
      .from('transactions')
      .update({'category_id': categoryId}).eq('id', txnId);
}

Future<void> deleteTxn(SupabaseClient db, String id) async {
  await db.from('transactions').delete().eq('id', id);
}

// ------------------------------------------------------------------- budgets

final budgetsProvider =
    FutureProvider.family<List<Budget>, DateTime>((ref, month) async {
  final db = ref.watch(supabaseProvider);
  final rows = await db
      .from('budgets')
      .select()
      .eq('month', isoDate(monthStart(month)));
  return rows.map(Budget.fromJson).toList();
});

Future<void> upsertBudget(
  SupabaseClient db, {
  required String categoryId,
  required DateTime month,
  required double amount,
}) async {
  await db.from('budgets').upsert({
    'user_id': _uid(db),
    'category_id': categoryId,
    'month': isoDate(monthStart(month)),
    'amount': amount,
  }, onConflict: 'user_id,category_id,month');
}

Future<void> deleteBudget(SupabaseClient db, String id) async {
  await db.from('budgets').delete().eq('id', id);
}

// --------------------------------------------------------------- plaid calls

class PlaidService {
  final SupabaseClient db;
  PlaidService(this.db);

  Future<({String linkToken, String url})> createHostedLink() async {
    final res = await db.functions
        .invoke('plaid-link', body: {'action': 'create_hosted_link'});
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return (
      linkToken: data['link_token'] as String,
      url: data['hosted_link_url'] as String
    );
  }

  /// Returns true when the link session finished and accounts were saved.
  Future<bool> completeLink(String linkToken) async {
    final res = await db.functions.invoke('plaid-link',
        body: {'action': 'complete', 'link_token': linkToken});
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return data['linked'] == true;
  }

  Future<void> syncNow() async {
    final res = await db.functions.invoke('plaid-sync');
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
  }
}

final plaidServiceProvider =
    Provider<PlaidService>((ref) => PlaidService(ref.watch(supabaseProvider)));

/// Invalidate everything money-related after a sync or edit.
void refreshData(WidgetRef ref) {
  ref.invalidate(accountsProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(monthTxnsProvider);
  ref.invalidate(budgetsProvider);
}
