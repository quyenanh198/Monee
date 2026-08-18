/// Pure CSV import parsing/mapping. No Flutter imports — unit-tested.
///
/// Handles RFC-4180 quoting, auto-detects the delimiter (`,` `;` or tab),
/// auto-maps columns from common header names, and parses flexible date and
/// amount formats found in US bank exports.
library;

class ImportedTxn {
  final DateTime date;
  final double amount; // app convention: > 0 = money out
  final String? description;

  const ImportedTxn({
    required this.date,
    required this.amount,
    required this.description,
  });
}

class CsvMapping {
  final int dateCol;
  final int amountCol;
  final int? descCol;

  /// Bank exports often use negative = money out; the app uses positive.
  final bool invertSign;

  const CsvMapping({
    required this.dateCol,
    required this.amountCol,
    this.descCol,
    this.invertSign = false,
  });
}

String detectDelimiter(String text) {
  final line = text.split('\n').firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => '',
      );
  var best = ',';
  var bestCount = -1;
  for (final d in [',', ';', '\t']) {
    final count = d.allMatches(line).length;
    if (count > bestCount) {
      best = d;
      bestCount = count;
    }
  }
  return best;
}

/// RFC-4180-style parser. Returns non-empty rows of cells.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  final d = delimiter ?? detectDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.isEmpty) {
      inQuotes = true;
    } else if (ch == d) {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else if (ch != '\r') {
      cell.write(ch);
    }
  }
  endRow();
  return rows;
}

int? _findCol(List<String> header, List<String> needles) {
  for (var i = 0; i < header.length; i++) {
    final h = header[i].trim().toLowerCase();
    for (final n in needles) {
      if (h.contains(n)) return i;
    }
  }
  return null;
}

/// Guesses the mapping from a header row. Returns null when no date/amount
/// column can be identified.
CsvMapping? autoMap(List<String> header) {
  final date = _findCol(header, ['date', 'ngày', 'ngay']);
  final amount = _findCol(header, ['amount', 'số tiền', 'so tien', 'value']);
  final desc = _findCol(
      header, ['description', 'memo', 'mô tả', 'mo ta', 'name', 'payee', 'merchant', 'detail']);
  if (date == null || amount == null) return null;
  return CsvMapping(dateCol: date, amountCol: amount, descCol: desc);
}

/// Accepts yyyy-MM-dd (ISO), MM/dd/yyyy or dd/MM/yyyy (disambiguated by
/// value; ties resolve to MM/dd — US bank exports).
DateTime? parseFlexibleDate(String s) {
  final t = s.trim();
  final iso = DateTime.tryParse(t);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(t);
  if (m == null) return null;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  final year = int.parse(m.group(3)!);
  final (month, day) = a > 12 ? (b, a) : (a, b);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

/// Accepts "$1,234.56", "(12.50)" (negative), "-12.5".
double? parseAmount(String s) {
  var t = s.trim().replaceAll(r'$', '').replaceAll(',', '').replaceAll(' ', '');
  var negative = false;
  if (t.startsWith('(') && t.endsWith(')')) {
    negative = true;
    t = t.substring(1, t.length - 1);
  }
  final v = double.tryParse(t);
  if (v == null) return null;
  return negative ? -v : v;
}

/// Maps data rows (header excluded) into transactions; invalid rows are
/// counted, not imported.
({List<ImportedTxn> txns, int skipped}) mapCsv(
  List<List<String>> rows,
  CsvMapping m,
) {
  final out = <ImportedTxn>[];
  var skipped = 0;
  for (final r in rows) {
    if (m.dateCol >= r.length || m.amountCol >= r.length) {
      skipped++;
      continue;
    }
    final date = parseFlexibleDate(r[m.dateCol]);
    final raw = parseAmount(r[m.amountCol]);
    if (date == null || raw == null) {
      skipped++;
      continue;
    }
    final desc = m.descCol != null && m.descCol! < r.length
        ? r[m.descCol!].trim()
        : '';
    out.add(ImportedTxn(
      date: date,
      amount: m.invertSign ? -raw : raw,
      description: desc.isEmpty ? null : desc,
    ));
  }
  return (txns: out, skipped: skipped);
}
