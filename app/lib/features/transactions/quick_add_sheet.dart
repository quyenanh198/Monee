import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/parsing.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Quick Add — the fastest path to record a transaction (spec §3):
/// amount first (autofocus), expense/income toggle, category icon grid,
/// account, optional note, big Save + "save & add another".
Future<void> showQuickAddSheet(BuildContext context, WidgetRef ref) async {
  final accounts = ref.read(accountsProvider).valueOrNull ?? [];
  final cats = ref.read(categoriesProvider).valueOrNull ?? [];
  final messenger = ScaffoldMessenger.of(context);
  if (accounts.isEmpty) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Tạo một tài khoản trước (Tài khoản → Thêm).')));
    return;
  }

  final form = _QuickAddForm(
      accounts: accounts, cats: cats, ref: ref, messenger: messenger);

  // Spec §3: bottom sheet on mobile, centered modal on web/desktop.
  if (MediaQuery.sizeOf(context).width >= kWideBreakpoint) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: form,
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => form,
  );
}

class _QuickAddForm extends StatefulWidget {
  final List<Account> accounts;
  final List<Category> cats;
  final WidgetRef ref;
  final ScaffoldMessengerState messenger;
  const _QuickAddForm(
      {required this.accounts,
      required this.cats,
      required this.ref,
      required this.messenger});

  @override
  State<_QuickAddForm> createState() => _QuickAddFormState();
}

class _QuickAddFormState extends State<_QuickAddForm> {
  final amount = TextEditingController();
  final note = TextEditingController();
  bool isExpense = true;
  String? categoryId;
  late String accountId = widget.accounts.first.id;
  late List<Category> cats = List.of(widget.cats);
  bool saving = false;

  /// Minimal category management: add a new personal category.
  Future<void> _manageCategories(BuildContext context) async {
    final name = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm danh mục'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên danh mục'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              if (name.text.trim().isEmpty) return;
              await createCategory(
                  widget.ref.read(supabaseProvider), name.text.trim());
              nav.pop(true);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (added == true) {
      widget.ref.invalidate(categoriesProvider);
      final updated = await widget.ref.read(categoriesProvider.future);
      if (mounted) setState(() => cats = updated);
    }
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<bool> _save() async {
    final raw = parseAmount(amount.text);
    if (raw == null || raw <= 0) {
      widget.messenger.showSnackBar(
          const SnackBar(content: Text('Số tiền không hợp lệ — chưa lưu')));
      return false;
    }
    setState(() => saving = true);
    try {
      await upsertManualTxn(
        widget.ref.read(supabaseProvider),
        accountId: accountId,
        amount: isExpense ? raw.abs() : -raw.abs(),
        date: DateTime.now(),
        description: note.text.trim().isEmpty ? null : note.text.trim(),
        categoryId: categoryId,
        note: null,
        tags: const [],
      );
    } catch (e) {
      widget.messenger.showSnackBar(SnackBar(content: Text('Lỗi lưu: $e')));
      if (mounted) setState(() => saving = false);
      return false;
    }
    refreshData(widget.ref);
    widget.messenger
        .showSnackBar(const SnackBar(content: Text('Đã lưu giao dịch')));
    if (mounted) setState(() => saving = false);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text('Thêm giao dịch nhanh',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: moneyStyle(context, size: 32),
              decoration: const InputDecoration(
                hintText: '0',
                helperText: 'Nhập số tiền (USD)',
                helperMaxLines: 1,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: true,
                    label: Text('Chi tiêu'),
                    icon: Icon(LucideIcons.wallet, size: 16)),
                ButtonSegment(
                    value: false,
                    label: Text('Thu nhập'),
                    icon: Icon(LucideIcons.arrowUp, size: 16)),
              ],
              selected: {isExpense},
              onSelectionChanged: (s) => setState(() => isExpense = s.first),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text('Danh mục',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton(
                onPressed: () => _manageCategories(context),
                child: const Text('Quản lý'),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  _CategoryCell(
                    name: c.name,
                    icon: categoryIcon(c.icon),
                    selected: categoryId == c.id,
                    onTap: () => setState(
                        () => categoryId = categoryId == c.id ? null : c.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Tài khoản'),
              items: [
                for (final a in widget.accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => accountId = v ?? accountId,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration:
                  const InputDecoration(labelText: 'Ghi chú (tùy chọn)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final nav = Navigator.of(context);
                      if (await _save()) nav.pop();
                    },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Lưu', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (await _save()) {
                        amount.clear();
                        note.clear();
                        setState(() => categoryId = null);
                      }
                    },
              child: Text('Lưu & thêm tiếp',
                  style: TextStyle(color: primary)),
            ),
            Text(
              'Ngày: hôm nay (${shortDate(DateTime.now())}) — sửa chi tiết hơn ở trang Giao dịch.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedColor(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCell extends StatelessWidget {
  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryCell(
      {required this.name,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final border = Theme.of(context).brightness == Brightness.dark
        ? MoneeColors.darkBorder
        : MoneeColors.lightBorder;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 82,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? primary : border, width: selected ? 1.5 : 1),
          color: selected ? primary.withValues(alpha: 0.08) : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.10),
            ),
            child: Icon(icon, size: 18, color: primary),
          ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}
