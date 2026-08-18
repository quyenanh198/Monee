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

/// Quotes a user-typed term for a PostgREST `.or()` filter. Without quoting,
/// commas/parentheses in the input break the filter syntax.
String _orQuote(String term) {
  final escaped = term.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"%$escaped%"';
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
    final term = _orQuote(f.search);
    q = q.or(
        'merchant_name.ilike.$term,description.ilike.$term,note.ilike.$term');
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

/// Transactions for the last 6 calendar months, inclusive of current (reports).
final sixMonthTxnsProvider = FutureProvider<List<Txn>>((ref) async {
  final db = ref.watch(supabaseProvider);
  final from = addMonths(DateTime.now(), -5);
  final rows = await db
      .from('transactions')
      .select()
      .gte('date', isoDate(from))
      .order('date');
  return rows.map(Txn.fromJson).toList();
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

/// Splits [parent] into [parts] (each a signed amount + category). Children
/// carry parent_txn_id; aggregations then count the children instead of the
/// parent (see budget_logic.effectiveTxns).
Future<void> splitTxn(
  SupabaseClient db,
  Txn parent,
  List<({double amount, String? categoryId})> parts,
) async {
  await db.from('transactions').insert([
    for (final p in parts)
      {
        'user_id': _uid(db),
        'account_id': parent.accountId,
        'amount': p.amount,
        'date': isoDate(parent.date),
        'description': '${parent.title} (tách)',
        'category_id': p.categoryId,
        'parent_txn_id': parent.id,
      },
  ]);
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
/// of transactions updated.
Future<int> applyRuleToExisting(SupabaseClient db, Rule rule) async {
  final term = _orQuote(rule.pattern);
  var q = db
      .from('transactions')
      .update({'category_id': rule.categoryId}).isFilter('category_id', null);
  q = switch (rule.matchField) {
    'merchant' => q.ilike('merchant_name', '%${rule.pattern}%'),
    'description' => q.ilike('description', '%${rule.pattern}%'),
    _ => q.or('merchant_name.ilike.$term,description.ilike.$term'),
  };
  final rows = await q.select('id');
  return rows.length;
}

// --------------------------------------------------------------------- goals

final goalsProvider = FutureProvider<List<Goal>>((ref) async {
  final db = ref.watch(supabaseProvider);
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
  final from = DateTime.now().subtract(const Duration(days: 180));
  final rows = await db
      .from('balance_snapshots')
      .select('date, total')
      .gte('date', isoDate(from))
      .order('date', ascending: true);
  return rows.map(BalanceSnapshot.fromJson).toList();
});

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
  ref.invalidate(sixMonthTxnsProvider);
  ref.invalidate(budgetsProvider);
  ref.invalidate(goalsProvider);
  ref.invalidate(snapshotsProvider);
}
