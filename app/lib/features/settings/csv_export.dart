/// Pure CSV export. No Flutter imports — unit-tested.
library;

import '../../models/models.dart';

String _cell(String? v) {
  if (v == null || v.isEmpty) return '';
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// RFC-4180-style CSV. Columns: date, amount, currency, account, category,
/// merchant, description, pending. Amount keeps the Plaid sign convention.
String transactionsToCsv(
  List<Txn> txns, {
  required Map<String, String> accountNames,
  required Map<String, String> categoryNames,
}) {
  final buf = StringBuffer(
      'date,amount,currency,account,category,merchant,description,pending\n');
  for (final t in txns) {
    buf.writeln([
      t.date.toIso8601String().substring(0, 10),
      t.amount.toStringAsFixed(2),
      t.currency,
      _cell(accountNames[t.accountId] ?? ''),
      _cell(t.categoryId == null ? '' : categoryNames[t.categoryId] ?? ''),
      _cell(t.merchantName),
      _cell(t.description),
      t.isPending.toString(),
    ].join(','));
  }
  return buf.toString();
}
