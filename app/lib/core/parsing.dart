/// Pure user-input parsing shared by the CSV importer and the transaction
/// form. No Flutter imports — unit-tested.
library;

/// Money in US ("$1,234.56"), VN/EU ("1.234,56"), parentheses-negative
/// ("(12.50)") and plain forms. Returns null when unparseable.
double? parseAmount(String s) {
  var t = s
      .trim()
      .replaceAll(r'$', '')
      .replaceAll('₫', '')
      .replaceAll(' ', '');
  if (t.isEmpty) return null;

  var negative = false;
  if (t.startsWith('(') && t.endsWith(')')) {
    negative = true;
    t = t.substring(1, t.length - 1);
  }
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  } else if (t.startsWith('+')) {
    t = t.substring(1);
  }

  final hasDot = t.contains('.');
  final hasComma = t.contains(',');
  String norm;
  if (hasDot && hasComma) {
    // The rightmost separator is the decimal one.
    if (t.lastIndexOf('.') > t.lastIndexOf(',')) {
      norm = t.replaceAll(',', ''); // 1,234.56
    } else {
      norm = t.replaceAll('.', '').replaceAll(',', '.'); // 1.234,56
    }
  } else if (hasComma) {
    final parts = t.split(',');
    // one comma with a non-3-digit tail = decimal comma (12,5); otherwise
    // thousands (1,234 / 1,234,567).
    norm = parts.length == 2 && parts[1].length != 3
        ? t.replaceAll(',', '.')
        : t.replaceAll(',', '');
  } else if (hasDot) {
    // multiple dots = VN/EU thousands (1.234.567); a single dot stays a
    // decimal point (ledger currency is USD).
    norm = t.split('.').length > 2 ? t.replaceAll('.', '') : t;
  } else {
    norm = t;
  }

  final v = double.tryParse(norm);
  if (v == null) return null;
  return negative ? -v : v;
}

/// Accepts yyyy-MM-dd (ISO) and d/m/yyyy-style dates. When both fields are
/// <= 12 the tie is broken by [dayFirst] (false = US MM/dd).
DateTime? parseFlexibleDate(String s, {bool dayFirst = false}) {
  final t = s.trim();
  final iso = DateTime.tryParse(t);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(t);
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  final year = int.parse(m.group(3)!);
  final (month, day) = a > 12
      ? (b, a)
      : b > 12
          ? (a, b)
          : dayFirst
              ? (b, a)
              : (a, b);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

/// Scans date strings to decide the field order of a whole file:
/// true = day-first (dd/MM), false = month-first (MM/dd), null = undecidable
/// (every value <= 12 in both positions).
bool? detectDayFirst(Iterable<String> samples) {
  final re = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.]\d{4}$');
  for (final s in samples) {
    final m = re.firstMatch(s.trim());
    if (m == null) continue;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    if (a > 12) return true;
    if (b > 12) return false;
  }
  return null;
}
