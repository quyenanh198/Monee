import 'package:intl/intl.dart';

// NumberFormat construction is expensive and money() runs once per tile per
// rebuild — cache one formatter per currency code.
final Map<String, NumberFormat> _moneyFormats = {};

/// Sign convention (Plaid): amount > 0 = money out, amount < 0 = money in.
String money(num amount, {String currency = 'USD', bool signed = false}) {
  final f = _moneyFormats.putIfAbsent(
      currency, () => NumberFormat.simpleCurrency(name: currency));
  if (!signed) return f.format(amount.abs());
  final sign = amount > 0 ? '-' : (amount < 0 ? '+' : '');
  return '$sign${f.format(amount.abs())}';
}

String shortDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String monthLabel(DateTime d) => DateFormat('MM/yyyy').format(d);

/// First day of the month of [d].
DateTime monthStart(DateTime d) => DateTime(d.year, d.month, 1);

/// First day of the month [offset] months after [d]'s month (offset may be negative).
DateTime addMonths(DateTime d, int offset) => DateTime(d.year, d.month + offset, 1);

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
