import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  final String? sub; // small line under the value (e.g. VND conversion)
  const KpiCard(
      {super.key,
      required this.label,
      required this.value,
      this.valueColor,
      this.sub});

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
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!, style: Theme.of(context).textTheme.bodySmall),
            ],
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

/// Resolves the kebab-case icon names stored on categories to Lucide icons.
IconData categoryIcon(String? name) => switch (name) {
      'utensils' => LucideIcons.utensils,
      'car' => LucideIcons.car,
      'home' => LucideIcons.home,
      'receipt' => LucideIcons.receipt,
      'shopping-bag' => LucideIcons.shoppingBag,
      'heart-pulse' => LucideIcons.heartPulse,
      'clapperboard' => LucideIcons.clapperboard,
      'plane' => LucideIcons.plane,
      'graduation-cap' => LucideIcons.graduationCap,
      'banknote' => LucideIcons.banknote,
      'arrow-left-right' => LucideIcons.arrowLeftRight,
      'circle-ellipsis' => LucideIcons.circleEllipsis,
      'tag' => LucideIcons.tag,
      _ => LucideIcons.circleDollarSign,
    };

class TxnTile extends StatelessWidget {
  final Txn txn;
  final String? categoryName;
  final String? categoryIconName;
  final VoidCallback? onTap;
  final Color? tileColor; // nền phân biệt tiền vào/ra (trang Giao dịch)
  const TxnTile(
      {super.key,
      required this.txn,
      this.categoryName,
      this.categoryIconName,
      this.onTap,
      this.tileColor});

  @override
  Widget build(BuildContext context) {
    final color =
        txn.isExpense ? MoneeColors.destructive : MoneeColors.accent;
    final iconBg = txn.isExpense
        ? MoneeColors.destructive.withValues(alpha: 0.10)
        : MoneeColors.accent.withValues(alpha: 0.12);
    return ListTile(
      onTap: onTap,
      tileColor: tileColor,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          categoryIconName != null
              ? categoryIcon(categoryIconName)
              : (txn.isExpense
                  ? LucideIcons.arrowUpRight
                  : LucideIcons.arrowDownLeft),
          size: 20,
          color: color,
        ),
      ),
      title: Text(txn.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          shortDate(txn.date),
          if (categoryName != null) categoryName!,
          if (txn.isPending) 'đang chờ',
          if (txn.tags.isNotEmpty) txn.tags.map((t) => '#$t').join(' '),
        ].join(' · '),
        style: TextStyle(fontSize: 12.5, color: mutedColor(context)),
      ),
      trailing: Text(
        money(txn.amount, currency: txn.currency, signed: true),
        style: moneyStyle(context, size: 15, color: color),
      ),
    );
  }
}

/// Small pill with a colored dot + category name (mockup-style chip).
class CategoryChip extends StatelessWidget {
  final String? categoryId;
  final String? name;
  const CategoryChip({super.key, required this.categoryId, required this.name});

  @override
  Widget build(BuildContext context) {
    final key = categoryId ?? '';
    final color = categoryColor(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(name ?? 'Chưa phân loại',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
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
