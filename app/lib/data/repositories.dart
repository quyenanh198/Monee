import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import '../models/models.dart';

final supabaseProvider =
    Provider<SupabaseClient>((_) => Supabase.instance.client);

String _uid(SupabaseClient db) => db.auth.currentUser!.id;

// ---------------------------------------------------------------------- auth

final _authChangesProvider = StreamProvider<AuthState>(
    (_) => Supabase.instance.client.auth.onAuthStateChange);

/// The signed-in user id, kept live across sign-out/sign-in. Every data
/// provider watches this so a user switch drops the previous user's cache
/// instead of serving it to the next account.
final currentUserIdProvider = Provider<String?>((ref) {
  final state = ref.watch(_authChangesProvider).valueOrNull;
  return state?.session?.user.id ??
      Supabase.instance.client.auth.currentUser?.id;
});

// ------------------------------------------------------------------- helpers

/// PostgREST silently caps unbounded selects at the project's max-rows
/// (1000 by default): page explicitly so big months are never truncated.
Future<List<Map<String, dynamic>>> _fetchAll(
    Future<List<Map<String, dynamic>>> Function(int from, int to) page) async {
  const size = 1000;
  final out = <Map<String, dynamic>>[];
  for (var start = 0;; start += size) {
    final rows = await page(start, start + size - 1);
    out.addAll(rows);
    if (rows.length < size) return out;
  }
}

/// Quotes a value for a PostgREST `.or()` filter — commas/parentheses in the
/// input must not break the filter syntax.
String _pgQuote(String v) =>
    '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// Escapes LIKE wildcards so a rule pattern matches literally, exactly like
/// matchRule() does on the Edge Function side.
String _escapeLike(String v) =>
    v.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

// ------------------------------------------------------------------ accounts

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
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
    // toUtc: a local wall-clock ISO string has no offset and lands shifted
    // by the device's timezone in a timestamptz column.
    'balance_updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}

/// Deletes an account. If it was the last account of a Plaid item, also
/// unlinks the item (removes it at Plaid and deletes our plaid_items row) so
/// no orphan item keeps syncing.
Future<void> deleteAccount(SupabaseClient db, String id) async {
  final row = await db
      .from('accounts')
      .select('plaid_item_id')
      .eq('id', id)
      .single();
  final itemId = row['plaid_item_id'] as String?;

  await db.from('accounts').delete().eq('id', id);

  if (itemId != null) {
    final remaining = await db
        .from('accounts')
        .select('id')
        .eq('plaid_item_id', itemId)
        .limit(1);
    if (remaining.isEmpty) {
      final res = await db.functions
          .invoke('plaid-link', body: {'action': 'unlink', 'item_id': itemId});
      final data = res.data as Map<String, dynamic>?;
      if (data?['error'] != null) throw Exception(data!['error']);
    }
  }
}

// ---------------------------------------------------------------- categories

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final rows = await db.from('categories').select().order('name');
  return rows.map(Category.fromJson).toList();
});

/// {category id → name} — the lookup every screen needs; built once.
final categoryNamesProvider = Provider<Map<String, String>>((ref) {
  final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
  return {for (final c in cats) c.id: c.name};
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
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final f = ref.watch(txnFilterProvider);
  final limit = ref.watch(txnPageSizeProvider);

  final rows = await _fetchAll((from, to) {
    var q = db.from('transactions').select();
    if (f.accountId != null) q = q.eq('account_id', f.accountId!);
    if (f.categoryId != null) q = q.eq('category_id', f.categoryId!);
    if (f.month != null) {
      q = q
          .gte('date', isoDate(monthStart(f.month!)))
          .lt('date', isoDate(addMonths(f.month!, 1)));
    }
    if (f.search.isNotEmpty) {
      final term = _pgQuote('%${f.search}%');
      q = q.or(
          'merchant_name.ilike.$term,description.ilike.$term,note.ilike.$term');
    }
    final upper = to < limit - 1 ? to : limit - 1;
    return q.order('date', ascending: false).range(from, upper);
  });
  return rows.take(limit).map(Txn.fromJson).toList();
});

/// Realtime stream of the 10 most recent transactions (dashboard).
final recentTxnsProvider = StreamProvider<List<Txn>>((ref) {
  final db = ref.watch(supabaseProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <Txn>[]);
  return db
      .from('transactions')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .order('date')
      .limit(10)
      .map((rows) => rows.map(Txn.fromJson).toList());
});

/// Transactions for the last 6 calendar months, inclusive of current (reports).
final sixMonthTxnsProvider = FutureProvider<List<Txn>>((ref) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final from = addMonths(DateTime.now(), -5);
  final rows = await _fetchAll((start, end) => db
      .from('transactions')
      .select()
      .gte('date', isoDate(from))
      .order('date', ascending: true)
      .range(start, end));
  return rows.map(Txn.fromJson).toList();
});

/// All transactions in one calendar month (dashboard donut, budgets).
final monthTxnsProvider =
    FutureProvider.family<List<Txn>, DateTime>((ref, month) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final rows = await _fetchAll((start, end) => db
      .from('transactions')
      .select()
      .gte('date', isoDate(monthStart(month)))
      .lt('date', isoDate(addMonths(month, 1)))
      .order('date', ascending: true)
      .range(start, end));
  return rows.map(Txn.fromJson).toList();
});

/// Every transaction row, newest first (CSV export) — paginated.
Future<List<Txn>> fetchAllTxns(SupabaseClient db) async {
  final rows = await _fetchAll((start, end) => db
      .from('transactions')
      .select()
      .order('date', ascending: false)
      .range(start, end));
  return rows.map(Txn.fromJson).toList();
}

Future<void> upsertManualTxn(
  SupabaseClient db, {
  String? id,
  required String accountId,
  required double amount,
  required DateTime date,
  String? description,
  String? categoryId,
  String? note,
  List<String> tags = const [],
}) async {
  final row = {
    'user_id': _uid(db),
    'account_id': accountId,
    'amount': amount,
    'date': isoDate(date),
    'description': description,
    'category_id': categoryId,
    'note': note,
    'tags': tags,
  };
  if (id == null) {
    await db.from('transactions').insert(row);
  } else {
    await db.from('transactions').update(row).eq('id', id);
  }
}

/// Splits [parent] into [parts] via the split_transaction RPC — atomic
/// (replaces any previous children under a row lock, so concurrent splits
/// can't double-count) and server-validated (parts must sum to the parent).
Future<void> splitTxn(
  SupabaseClient db,
  Txn parent,
  List<({double amount, String? categoryId})> parts,
) async {
  await db.rpc('split_transaction', params: {
    'p_parent': parent.id,
    'p_parts': [
      for (final p in parts) {'amount': p.amount, 'category_id': p.categoryId},
    ],
  });
}

/// Removes all split children of a parent transaction.
Future<void> unsplitTxn(SupabaseClient db, String parentId) async {
  await db.from('transactions').delete().eq('parent_txn_id', parentId);
}

/// Updates the user-editable metadata of any transaction (Plaid rows keep
/// their amount/date/merchant from sync; only these fields are ours).
Future<void> updateTxnMeta(
  SupabaseClient db,
  String txnId, {
  String? categoryId,
  String? note,
  List<String> tags = const [],
}) async {
  await db.from('transactions').update({
    'category_id': categoryId,
    'note': note,
    'tags': tags,
  }).eq('id', txnId);
}

Future<void> deleteTxn(SupabaseClient db, String id) async {
  await db.from('transactions').delete().eq('id', id);
}

// ------------------------------------------------------------------- budgets

final budgetsProvider =
    FutureProvider.family<List<Budget>, DateTime>((ref, month) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
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
  bool rollover = false,
}) async {
  await db.from('budgets').upsert({
    'user_id': _uid(db),
    'category_id': categoryId,
    'month': isoDate(monthStart(month)),
    'amount': amount,
    'rollover': rollover,
  }, onConflict: 'user_id,category_id,month');
}

Future<void> deleteBudget(SupabaseClient db, String id) async {
  await db.from('budgets').delete().eq('id', id);
}

// --------------------------------------------------------------------- rules

final rulesProvider = FutureProvider<List<Rule>>((ref) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final rows = await db.from('rules').select().order('created_at');
  return rows.map(Rule.fromJson).toList();
});

Future<void> createRule(
  SupabaseClient db, {
  required String pattern,
  required String matchField,
  required String categoryId,
}) async {
  await db.from('rules').insert({
    'user_id': _uid(db),
    'pattern': pattern,
    'match_field': matchField,
    'category_id': categoryId,
  });
}

Future<void> deleteRule(SupabaseClient db, String id) async {
  await db.from('rules').delete().eq('id', id);
}

/// Applies a rule to existing uncategorized transactions. Returns the number
/// of transactions updated. LIKE wildcards in the pattern are escaped so the
/// match is a literal substring — identical to matchRule() during sync.
Future<int> applyRuleToExisting(SupabaseClient db, Rule rule) async {
  final pattern = '%${_escapeLike(rule.pattern)}%';
  final term = _pgQuote(pattern);
  var q = db
      .from('transactions')
      .update({'category_id': rule.categoryId}).isFilter('category_id', null);
  q = switch (rule.matchField) {
    'merchant' => q.ilike('merchant_name', pattern),
    'description' => q.ilike('description', pattern),
    _ => q.or('merchant_name.ilike.$term,description.ilike.$term'),
  };
  final rows = await q.select('id');
  return rows.length;
}

// --------------------------------------------------------------------- goals

final goalsProvider = FutureProvider<List<Goal>>((ref) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final rows = await db.from('goals').select().order('created_at');
  return rows.map(Goal.fromJson).toList();
});

Future<void> upsertGoal(
  SupabaseClient db, {
  String? id,
  required String name,
  required double targetAmount,
  double savedAmount = 0,
  String? accountId,
  DateTime? targetDate,
}) async {
  final row = {
    'user_id': _uid(db),
    'name': name,
    'target_amount': targetAmount,
    'saved_amount': savedAmount,
    'account_id': accountId,
    'target_date': targetDate == null ? null : isoDate(targetDate),
  };
  if (id == null) {
    await db.from('goals').insert(row);
  } else {
    await db.from('goals').update(row).eq('id', id);
  }
}

Future<void> deleteGoal(SupabaseClient db, String id) async {
  await db.from('goals').delete().eq('id', id);
}

// ---------------------------------------------------------------- snapshots

/// Net-worth history, oldest first (last ~180 days).
final snapshotsProvider = FutureProvider<List<BalanceSnapshot>>((ref) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final from = DateTime.now().subtract(const Duration(days: 180));
  final rows = await db
      .from('balance_snapshots')
      .select('date, total')
      .gte('date', isoDate(from))
      .order('date', ascending: true);
  return rows.map(BalanceSnapshot.fromJson).toList();
});

// --------------------------------------------------------------- plaid calls

/// Bank connections with their health (client may read these columns only).
final plaidItemsProvider = FutureProvider<List<PlaidItem>>((ref) async {
  final db = ref.watch(supabaseProvider);
  if (ref.watch(currentUserIdProvider) == null) return const [];
  final rows =
      await db.from('plaid_items').select('id, institution_name, status');
  return rows.map(PlaidItem.fromJson).toList();
});

class PlaidService {
  final SupabaseClient db;
  PlaidService(this.db);

  /// New link, or Link *update mode* to re-authenticate [itemId] after
  /// ITEM_LOGIN_REQUIRED (keeps the item's accounts and history).
  Future<({String linkToken, String url})> createHostedLink(
      {String? itemId}) async {
    final res = await db.functions.invoke('plaid-link', body: {
      'action': 'create_hosted_link',
      if (itemId != null) 'item_id': itemId,
    });
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

  /// Throws when the sync response carries per-item failures — a 200 with
  /// results[i].error is still a failed sync for that bank.
  Future<void> syncNow() async {
    final res = await db.functions.invoke('plaid-sync');
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    final results = (data['results'] as List?) ?? const [];
    final errors = [
      for (final r in results)
        if (r is Map && r['error'] != null) r['error'].toString(),
    ];
    if (errors.isNotEmpty) {
      throw Exception(
          'Lỗi ${errors.length}/${results.length} kết nối: ${errors.first}');
    }
  }
}

final plaidServiceProvider =
    Provider<PlaidService>((ref) => PlaidService(ref.watch(supabaseProvider)));

/// Invalidate everything money-related after a sync or edit.
void refreshData(WidgetRef ref) {
  ref.invalidate(accountsProvider);
  ref.invalidate(transactionsProvider);
  ref.invalidate(monthTxnsProvider);
  ref.invalidate(sixMonthTxnsProvider);
  ref.invalidate(budgetsProvider);
  ref.invalidate(goalsProvider);
  ref.invalidate(snapshotsProvider);
  ref.invalidate(plaidItemsProvider);
}
