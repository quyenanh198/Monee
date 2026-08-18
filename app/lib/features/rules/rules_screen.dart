import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

const _fieldLabels = {
  'any': 'Merchant hoặc mô tả',
  'merchant': 'Chỉ merchant',
  'description': 'Chỉ mô tả',
};

class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);
    final categories = ref.watch(categoriesProvider);
    final catList = categories.valueOrNull ?? <Category>[];
    final catNames = ref.watch(categoryNamesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rules phân loại tự động')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Thêm rule',
        onPressed:
            catList.isEmpty ? null : () => _addRule(context, ref, catList),
        child: const Icon(LucideIcons.plus),
      ),
      body: AsyncBody(
        value: rules,
        builder: (list) => list.isEmpty
            ? const EmptyState(
                'Chưa có rule nào.\nVí dụ: "NETFLIX" → Giải trí — giao dịch '
                'mới từ ngân hàng sẽ được tự phân loại.')
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Column(children: [
                      for (final r in list)
                        ListTile(
                          leading: const Icon(LucideIcons.wand2),
                          title: Text('"${r.pattern}" → '
                              '${catNames[r.categoryId] ?? '?'}'),
                          subtitle:
                              Text(_fieldLabels[r.matchField] ?? r.matchField),
                          trailing: IconButton(
                            tooltip: 'Xóa rule',
                            icon: const Icon(LucideIcons.trash2, size: 18),
                            onPressed: () async {
                              await deleteRule(
                                  ref.read(supabaseProvider), r.id);
                              ref.invalidate(rulesProvider);
                            },
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Rule chỉ áp cho giao dịch MỚI chưa có danh mục — không '
                    'bao giờ ghi đè danh mục bạn đã chọn tay.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _addRule(
      BuildContext context, WidgetRef ref, List<Category> cats) async {
    final pattern = TextEditingController();
    String field = 'any';
    String categoryId = cats.first.id;
    var applyOld = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Thêm rule'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: pattern,
                decoration: const InputDecoration(
                    labelText: 'Chứa chuỗi',
                    helperText: 'Không phân biệt hoa thường'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: field,
                decoration: const InputDecoration(labelText: 'So khớp với'),
                items: [
                  for (final e in _fieldLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => field = v ?? 'any',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                decoration: const InputDecoration(labelText: 'Gán danh mục'),
                items: [
                  for (final c in cats)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => categoryId = v ?? categoryId,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: applyOld,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Áp luôn cho giao dịch cũ chưa phân loại',
                    style: TextStyle(fontSize: 14)),
                onChanged: (v) => setState(() => applyOld = v ?? true),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                final p = pattern.text.trim();
                if (p.isEmpty) return;
                final nav = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final db = ref.read(supabaseProvider);
                try {
                  await createRule(db,
                      pattern: p, matchField: field, categoryId: categoryId);
                  var applied = 0;
                  if (applyOld) {
                    applied = await applyRuleToExisting(
                        db,
                        Rule(
                            id: '',
                            pattern: p,
                            matchField: field,
                            categoryId: categoryId));
                    refreshData(ref);
                  }
                  ref.invalidate(rulesProvider);
                  nav.pop();
                  messenger.showSnackBar(SnackBar(
                      content: Text(applyOld
                          ? 'Đã tạo rule — áp cho $applied giao dịch cũ'
                          : 'Đã tạo rule')));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
