import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import 'csv_import.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _text = TextEditingController();
  String? _accountId;
  List<List<String>>? _rows; // parsed, header included
  CsvMapping? _mapping;
  bool? _dayFirstChoice; // null = auto-detect from the file
  bool _busy = false;

  void _parse() {
    final rows = parseCsv(_text.text);
    if (rows.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cần ít nhất 1 dòng header và 1 dòng dữ liệu')));
      return;
    }
    setState(() {
      _rows = rows;
      _mapping = autoMap(rows.first) ??
          CsvMapping(dateCol: 0, amountCol: rows.first.length > 1 ? 1 : 0);
    });
  }

  Future<void> _import(List<ImportedTxn> txns) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final db = ref.read(supabaseProvider);
      final uid = db.auth.currentUser!.id;
      for (var i = 0; i < txns.length; i += 500) {
        final chunk = txns.sublist(i, i + 500 > txns.length ? txns.length : i + 500);
        await db.from('transactions').insert([
          for (final t in chunk)
            {
              'user_id': uid,
              'account_id': _accountId,
              'amount': t.amount,
              'date': isoDate(t.date),
              'description': t.description,
              'tags': ['import'],
            },
        ]);
      }
      refreshData(ref);
      messenger.showSnackBar(
          SnackBar(content: Text('Đã nhập ${txns.length} giao dịch')));
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    _accountId ??= accounts.isEmpty ? null : accounts.first.id;

    final rows = _rows;
    final mapping = _mapping;
    final header = rows?.first;
    // Date field order: explicit choice wins, else scan the file (a single
    // day > 12 anywhere decides), else default to US MM/dd.
    final detectedDayFirst = rows == null || mapping == null
        ? null
        : detectDayFirst(rows
            .sublist(1)
            .where((r) => mapping.dateCol < r.length)
            .map((r) => r[mapping.dateCol]));
    final effMapping = mapping == null
        ? null
        : CsvMapping(
            dateCol: mapping.dateCol,
            amountCol: mapping.amountCol,
            descCol: mapping.descCol,
            invertSign: mapping.invertSign,
            dayFirst: _dayFirstChoice ?? detectedDayFirst ?? false,
          );
    final mapped = rows != null && effMapping != null
        ? mapCsv(rows.sublist(1), effMapping)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Nhập CSV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Nhập vào tài khoản'),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLines: 8,
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Dán nội dung CSV (kèm dòng header)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.scanLine, size: 18),
            label: const Text('Phân tích'),
            onPressed: _parse,
          ),
          if (rows != null && mapping != null && header != null) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _colDrop('Cột ngày', mapping.dateCol, header,
                  (v) => _remap(dateCol: v)),
              _colDrop('Cột số tiền', mapping.amountCol, header,
                  (v) => _remap(amountCol: v)),
              _colDrop('Cột mô tả', mapping.descCol, header,
                  (v) => _remap(descCol: v),
                  allowNone: true),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<int>(
                  initialValue: _dayFirstChoice == null
                      ? 0
                      : (_dayFirstChoice! ? 2 : 1),
                  decoration: const InputDecoration(labelText: 'Định dạng ngày'),
                  items: [
                    DropdownMenuItem(
                        value: 0,
                        child: Text(detectedDayFirst == null
                            ? 'Tự động'
                            : 'Tự động (${detectedDayFirst ? 'dd/MM' : 'MM/dd'})')),
                    const DropdownMenuItem(value: 1, child: Text('MM/dd/yyyy')),
                    const DropdownMenuItem(value: 2, child: Text('dd/MM/yyyy')),
                  ],
                  onChanged: (v) => setState(
                      () => _dayFirstChoice = v == 0 ? null : v == 2),
                ),
              ),
            ]),
            SwitchListTile(
              value: mapping.invertSign,
              contentPadding: EdgeInsets.zero,
              title: const Text('Đảo dấu số tiền', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Bật nếu file dùng số ÂM cho tiền ra (app dùng số dương = chi)',
                  style: TextStyle(fontSize: 12)),
              onChanged: (v) => _remap(invertSign: v),
            ),
            if (mapped != null) ...[
              const SizedBox(height: 8),
              Text(
                  'Đọc được ${mapped.txns.length} giao dịch'
                  '${mapped.skipped > 0 ? ' · bỏ qua ${mapped.skipped} dòng lỗi' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (final t in mapped.txns.take(5))
                    ListTile(
                      dense: true,
                      title: Text(t.description ?? '(không mô tả)',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(shortDate(t.date)),
                      trailing: Text(money(t.amount, signed: true),
                          style: moneyStyle(context, size: 13.5)),
                    ),
                  if (mapped.txns.length > 5)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('… và ${mapped.txns.length - 5} giao dịch nữa',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(LucideIcons.download, size: 18),
                label: Text(_busy
                    ? 'Đang nhập…'
                    : 'Nhập ${mapped.txns.length} giao dịch'),
                onPressed: _busy || mapped.txns.isEmpty || _accountId == null
                    ? null
                    : () => _import(mapped.txns),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _remap({int? dateCol, int? amountCol, int? descCol, bool? invertSign}) {
    final m = _mapping!;
    setState(() {
      _mapping = CsvMapping(
        dateCol: dateCol ?? m.dateCol,
        amountCol: amountCol ?? m.amountCol,
        descCol: descCol == -1 ? null : (descCol ?? m.descCol),
        invertSign: invertSign ?? m.invertSign,
      );
    });
  }

  Widget _colDrop(String label, int? value, List<String> header,
      ValueChanged<int> onChanged,
      {bool allowNone = false}) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<int>(
        initialValue: value ?? (allowNone ? -1 : 0),
        decoration: InputDecoration(labelText: label),
        items: [
          if (allowNone) const DropdownMenuItem(value: -1, child: Text('—')),
          for (var i = 0; i < header.length; i++)
            DropdownMenuItem(
                value: i,
                child: Text(header[i].trim().isEmpty ? 'Cột ${i + 1}' : header[i],
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }
}
