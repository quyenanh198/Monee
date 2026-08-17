import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../widgets/common.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(LucideIcons.plus),
        label: const Text('Thêm'),
        onPressed: () => _showAddSheet(context, ref),
      ),
      body: AsyncBody(
        value: accounts,
        builder: (list) => list.isEmpty
            ? const EmptyState('Chưa có tài khoản nào.')
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Column(children: [
                      for (final a in list)
                        ListTile(
                          leading: Icon(a.isManual
                              ? LucideIcons.wallet
                              : LucideIcons.landmark),
                          title: Text(a.name),
                          subtitle: Text([
                            a.type,
                            if (a.balanceUpdatedAt != null)
                              'cập nhật ${shortDate(a.balanceUpdatedAt!)}',
                          ].join(' · ')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                money(a.currentBalance, currency: a.currency),
                                style: moneyStyle(context, size: 15),
                              ),
                              IconButton(
                                tooltip: 'Xóa',
                                icon: const Icon(LucideIcons.trash2, size: 18),
                                onPressed: () =>
                                    _confirmDelete(context, ref, a.id, a.name),
                              ),
                            ],
                          ),
                        ),
                    ]),
                  ),
                ],
              ),
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(LucideIcons.landmark),
            title: const Text('Liên kết ngân hàng (Plaid)'),
            subtitle: const Text('Mở trang Plaid Link trong trình duyệt'),
            onTap: () {
              Navigator.pop(ctx);
              _linkBank(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.wallet),
            title: const Text('Tài khoản nhập tay'),
            onTap: () {
              Navigator.pop(ctx);
              _addManual(context, ref);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _linkBank(BuildContext context, WidgetRef ref) async {
    final plaid = ref.read(plaidServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final link = await plaid.createHostedLink();
      await launchUrl(Uri.parse(link.url),
          mode: LaunchMode.externalApplication);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hoàn tất liên kết'),
          content: const Text(
              'Hoàn thành các bước trong trang Plaid vừa mở, rồi bấm "Đã xong".'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                try {
                  final ok = await plaid.completeLink(link.linkToken);
                  if (ok) {
                    refreshData(ref);
                    nav.pop();
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Đã liên kết ngân hàng')));
                  } else {
                    messenger.showSnackBar(const SnackBar(
                        content: Text(
                            'Chưa xong phiên Link — thử lại sau vài giây')));
                  }
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                }
              },
              child: const Text('Đã xong'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _addManual(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final balance = TextEditingController(text: '0');
    String type = 'checking';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tài khoản nhập tay'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Tên')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Loại'),
            items: const [
              DropdownMenuItem(value: 'checking', child: Text('Thanh toán')),
              DropdownMenuItem(value: 'savings', child: Text('Tiết kiệm')),
              DropdownMenuItem(value: 'cash', child: Text('Tiền mặt')),
              DropdownMenuItem(value: 'credit', child: Text('Thẻ tín dụng')),
            ],
            onChanged: (v) => type = v ?? 'checking',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: balance,
            decoration: const InputDecoration(labelText: 'Số dư hiện tại'),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await createManualAccount(
                ref.read(supabaseProvider),
                name: name.text.trim().isEmpty ? 'Tài khoản' : name.text.trim(),
                type: type,
                balance: double.tryParse(balance.text) ?? 0,
              );
              refreshData(ref);
              nav.pop();
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xóa "$name"?'),
        content: const Text(
            'Mọi giao dịch của tài khoản này cũng bị xóa. Nếu đây là tài khoản '
            'cuối cùng của một ngân hàng liên kết, kết nối Plaid cũng được gỡ.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: MoneeColors.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await deleteAccount(ref.read(supabaseProvider), id);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
      refreshData(ref);
    }
  }
}
