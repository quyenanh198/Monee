/// Plain data models mapping Supabase rows. Sign convention (Plaid):
/// amount > 0 = money out (expense), amount < 0 = money in (income).
library;

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
        currentBalance: (j['current_balance'] as num?)?.toDouble() ?? 0,
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
  });

  bool get isManual => plaidTransactionId == null;
  bool get isExpense => amount > 0;
  String get title => merchantName ?? description ?? '(không mô tả)';

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        accountId: j['account_id'] as String,
        plaidTransactionId: j['plaid_transaction_id'] as String?,
        amount: (j['amount'] as num).toDouble(),
        currency: j['currency'] as String? ?? 'USD',
        date: DateTime.parse(j['date'] as String),
        merchantName: j['merchant_name'] as String?,
        description: j['description'] as String?,
        categoryId: j['category_id'] as String?,
        isPending: j['is_pending'] as bool? ?? false,
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

  const Budget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.amount,
  });

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        id: j['id'] as String,
        categoryId: j['category_id'] as String,
        month: DateTime.parse(j['month'] as String),
        amount: (j['amount'] as num).toDouble(),
      );
}
