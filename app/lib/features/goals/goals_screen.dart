import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final accounts = ref.watch(accountsProvider);
    final accList = accounts.valueOrNull ?? [];
    final balances = {for (final a in accList) a.id: a.currentBalance};

    return Scaffold(
      appBar: AppBar(title: const Text('Mục tiêu tiết kiệm')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Thêm mục tiêu',
        onPressed: () => _editGoal(context, ref, accounts: accList),
        child: const Icon(LucideIcons.plus),
      ),
      body: AsyncBody(
        value: goals,
        builder: (list) => list.isEmpty
            ? const EmptyState('Chưa có mục tiêu nào. Bấm + để thêm.')
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final g in list)
                    _GoalTile(
                      goal: g,
                      saved: g.accountId != null
                          ? (balances[g.accountId] ?? 0)
                          : g.savedAmount,
                      onTap: () => _editGoal(context, ref,
                          accounts: accList, existing: g),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref, {
    required List<Account> accounts,
    Goal? existing,
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final target = TextEditingController(
        text: existing?.targetAmount.toStringAsFixed(0) ?? '');
    final saved = TextEditingController(
        text: existing?.savedAmount.toStringAsFixed(0) ?? '0');
    String? accountId = existing?.accountId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Thêm mục tiêu' : 'Sửa mục tiêu'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên mục tiêu')),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                decoration:
                    const InputDecoration(labelText: 'Số tiền mục tiêu (USD)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: accountId,
                decoration: const InputDecoration(
                    labelText: 'Theo dõi qua tài khoản',
                    helperText: 'Để trống để tự nhập số đã tiết kiệm'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Tự nhập tay')),
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => accountId = v),
              ),
              if (accountId == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: saved,
                  decoration:
                      const InputDecoration(labelText: 'Đã tiết kiệm (USD)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ]),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  final nav = Navigator.of(ctx);
                  await deleteGoal(ref.read(supabaseProvider), existing.id);
                  ref.invalidate(goalsProvider);
                  nav.pop();
                },
                child: const Text('Xóa'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                final t = double.tryParse(target.text) ?? 0;
                if (name.text.trim().isEmpty || t <= 0) return;
                final nav = Navigator.of(ctx);
                await upsertGoal(
                  ref.read(supabaseProvider),
                  id: existing?.id,
                  name: name.text.trim(),
                  targetAmount: t,
                  savedAmount: double.tryParse(saved.text) ?? 0,
                  accountId: accountId,
                );
                ref.invalidate(goalsProvider);
                nav.pop();
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  final Goal goal;
  final double saved;
  final VoidCallback onTap;
  const _GoalTile(
      {required this.goal, required this.saved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = goal.targetAmount <= 0
        ? 0.0
        : (saved / goal.targetAmount).clamp(0.0, 1.0).toDouble();
    final done = saved >= goal.targetAmount;
    final color = done ? MoneeColors.accent : Theme.of(context).colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(done ? LucideIcons.checkCircle : LucideIcons.target,
                  size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(goal.name,
                      style: Theme.of(context).textTheme.titleSmall)),
              Text('${money(saved)} / ${money(goal.targetAmount)}',
                  style: moneyStyle(context, size: 14, color: color)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: progress, minHeight: 8, color: color),
            ),
          ]),
        ),
      ),
    );
  }
}
