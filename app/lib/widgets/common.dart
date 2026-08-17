import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// Renders an AsyncValue with standard loading/error states.
class AsyncBody<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  const AsyncBody({super.key, required this.value, required this.builder});

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Lỗi: $e', textAlign: TextAlign.center),
          ),
        ),
      );
}

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const KpiCard(
      {super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value,
                style: moneyStyle(context, size: 22, color: valueColor)),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  const EmptyState(this.message, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.inbox, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class TxnTile extends StatelessWidget {
  final Txn txn;
  final String? categoryName;
  final VoidCallback? onTap;
  const TxnTile({super.key, required this.txn, this.categoryName, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = txn.isExpense ? null : MoneeColors.accent;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        txn.isExpense ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft,
        color: color,
      ),
      title: Text(txn.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        shortDate(txn.date),
        if (categoryName != null) categoryName!,
        if (txn.isPending) 'đang chờ',
      ].join(' · ')),
      trailing: Text(
        money(txn.amount, currency: txn.currency, signed: true),
        style: moneyStyle(context, size: 15, color: color),
      ),
    );
  }
}

/// Stable color per category for charts.
Color categoryColor(String key) {
  const palette = [
    Color(0xFF3B82F6),
    Color(0xFF059669),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
    Color(0xFF6366F1),
    Color(0xFF84CC16),
    Color(0xFFEF4444),
  ];
  return palette[key.hashCode.abs() % palette.length];
}
