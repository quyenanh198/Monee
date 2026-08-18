/// Plain data models mapping Supabase rows. Sign convention (Plaid):
/// amount > 0 = money out (expense), amount < 0 = money in (income).
///
/// Parsing is deliberately tolerant: REST returns numerics as JSON numbers,
/// but Realtime change payloads deliver numeric columns as strings and
/// text[] as a Postgres array literal — both must decode identically or the
/// dashboard stream dies exactly on the cross-device update it exists for.
library;

double _toDouble(dynamic v) =>
    v is num ? v.toDouble() : double.parse(v.toString());

double _toDoubleOr(dynamic v, double fallback) =>
    v == null ? fallback : _toDouble(v);

bool _toBool(dynamic v) => v == true || v == 'true' || v == 't';

List<String> _toTags(dynamic v) {
  if (v is List) return v.cast<String>();
  if (v is String && v.startsWith('{') && v.endsWith('}')) {
    final inner = v.substring(1, v.length - 1);
    if (inner.isEmpty) return const [];
    return inner
        .split(',')
        .map((t) => t.replaceAll('"', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }
  return const [];
}

class Account {
  final String id;
  final String? plaidItemId;
  final String name;
  final String type;
  final String currency;
  final double currentBalance;
  final DateTime? balanceUpdatedAt;

  const Account({
    required this.id,
    required this.plaidItemId,
    required this.name,
    required this.type,
    required this.currency,
    required this.currentBalance,
    required this.balanceUpdatedAt,
  });

  bool get isManual => plaidItemId == null;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        plaidItemId: j['plaid_item_id'] as String?,
        name: j['name'] as String,
        type: j['type'] as String? ?? 'checking',
        currency: j['currency'] as String? ?? 'USD',
        currentBalance: _toDoubleOr(j['current_balance'], 0),
        balanceUpdatedAt: j['balance_updated_at'] == null
            ? null
            : DateTime.parse(j['balance_updated_at'] as String),
      );
}

class Txn {
  final String id;
  final String accountId;
  final String? plaidTransactionId;
  final double amount;
  final String currency;
  final DateTime date;
  final String? merchantName;
  final String? description;
  final String? categoryId;
  final bool isPending;
  final String? note;
  final List<String> tags;
  final String? parentTxnId; // set = this row is one part of a split

  const Txn({
    required this.id,
    required this.accountId,
    required this.plaidTransactionId,
    required this.amount,
    required this.currency,
    required this.date,
    required this.merchantName,
    required this.description,
    required this.categoryId,
    required this.isPending,
    this.note,
    this.tags = const [],
    this.parentTxnId,
  });

  bool get isManual => plaidTransactionId == null;
  bool get isExpense => amount > 0;
  bool get isSplitChild => parentTxnId != null;
  String get title => merchantName ?? description ?? '(không mô tả)';

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        accountId: j['account_id'] as String,
        plaidTransactionId: j['plaid_transaction_id'] as String?,
        amount: _toDouble(j['amount']),
        currency: j['currency'] as String? ?? 'USD',
        date: DateTime.parse(j['date'] as String),
        merchantName: j['merchant_name'] as String?,
        description: j['description'] as String?,
        categoryId: j['category_id'] as String?,
        isPending: _toBool(j['is_pending']),
        note: j['note'] as String?,
        tags: _toTags(j['tags']),
        parentTxnId: j['parent_txn_id'] as String?,
      );
}

class Category {
  final String id;
  final String? userId; // null = system default
  final String name;
  final String? icon;

  const Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.icon,
  });

  bool get isSystem => userId == null;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        userId: j['user_id'] as String?,
        name: j['name'] as String,
        icon: j['icon'] as String?,
      );
}

class Budget {
  final String id;
  final String categoryId;
  final DateTime month; // first day of month
  final double amount;
  final bool rollover; // leftover carries into next month

  const Budget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.amount,
    this.rollover = false,
  });

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        id: j['id'] as String,
        categoryId: j['category_id'] as String,
        month: DateTime.parse(j['month'] as String),
        amount: _toDouble(j['amount']),
        rollover: _toBool(j['rollover']),
      );
}

class Rule {
  final String id;
  final String pattern;
  final String matchField; // merchant | description | any
  final String categoryId;

  const Rule({
    required this.id,
    required this.pattern,
    required this.matchField,
    required this.categoryId,
  });

  factory Rule.fromJson(Map<String, dynamic> j) => Rule(
        id: j['id'] as String,
        pattern: j['pattern'] as String,
        matchField: j['match_field'] as String? ?? 'any',
        categoryId: j['category_id'] as String,
      );
}

class Goal {
  final String id;
  final String name;
  final double targetAmount;
  final double savedAmount; // used when accountId is null
  final String? accountId; // progress follows this account's balance
  final DateTime? targetDate;

  const Goal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    required this.accountId,
    required this.targetDate,
  });

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] as String,
        name: j['name'] as String,
        targetAmount: _toDouble(j['target_amount']),
        savedAmount: _toDoubleOr(j['saved_amount'], 0),
        accountId: j['account_id'] as String?,
        targetDate: j['target_date'] == null
            ? null
            : DateTime.parse(j['target_date'] as String),
      );
}

class PlaidItem {
  final String id;
  final String? institutionName;
  final String status; // active | error | login_required | disconnected

  const PlaidItem({
    required this.id,
    required this.institutionName,
    required this.status,
  });

  bool get needsRelogin => status == 'login_required';
  bool get healthy => status == 'active';

  factory PlaidItem.fromJson(Map<String, dynamic> j) => PlaidItem(
        id: j['id'] as String,
        institutionName: j['institution_name'] as String?,
        status: j['status'] as String? ?? 'active',
      );
}

class BalanceSnapshot {
  final DateTime date;
  final double total;

  const BalanceSnapshot({required this.date, required this.total});

  factory BalanceSnapshot.fromJson(Map<String, dynamic> j) => BalanceSnapshot(
        date: DateTime.parse(j['date'] as String),
        total: _toDouble(j['total']),
      );
}
