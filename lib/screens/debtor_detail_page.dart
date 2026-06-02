import 'package:flutter/material.dart';

import '../models/debtor.dart';
import '../utils/calculators.dart';
import '../utils/formatters.dart';
import '../widgets/mini_stat.dart';
import '../widgets/repayment_editor.dart';

/// 时间轴条目
class _TimelineItem {
  const _TimelineItem({
    required this.date,
    required this.amount,
    required this.description,
    this.isInterest = false,
    this.isManualInterest = false,
    this.isRepayment = true,
  });

  final DateTime date;
  final double amount;
  final String description;
  final bool isInterest;
  final bool isManualInterest;
  final bool isRepayment;
}

class DebtorDetailPage extends StatefulWidget {
  const DebtorDetailPage({
    super.key,
    required this.debtor,
    required this.onChanged,
  });

  final Debtor debtor;
  final VoidCallback onChanged;

  @override
  State<DebtorDetailPage> createState() => _DebtorDetailPageState();
}

class _DebtorDetailPageState extends State<DebtorDetailPage> {
  late Debtor _debtor;

  @override
  void initState() {
    super.initState();
    _debtor = widget.debtor;
    _debtor.repayments = List<Repayment>.from(_debtor.repayments);
    _debtor.interestEntries =
        List<InterestEntry>.from(_debtor.interestEntries);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncInterest());
  }

  Future<void> _syncInterest() async {
    if (settleInterest(_debtor)) await _saveAndNotify();
  }

  // --- business logic ---

  Future<void> _recordRepayment() async {
    await _syncInterest();
    if (_debtor.totalRemaining <= 0) {
      _showSnack('该债务已全部还清');
      return;
    }
    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const RepaymentEditor(),
    );
    if (result == null) return;

    final totalAmount = result['amount'] as double;
    final repayDate = result['date'] as DateTime;
    final currentInterest = _debtor.accruedInterest;

    double interestPortion, principalPortion;
    if (totalAmount <= currentInterest) {
      interestPortion = totalAmount;
      principalPortion = 0;
      _deductInterest(totalAmount);
    } else {
      interestPortion = currentInterest;
      principalPortion = totalAmount - currentInterest;
      _debtor.interestEntries.clear();
    }

    _debtor.repayments.add(Repayment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      amount: totalAmount,
      interestPortion: interestPortion,
      principalPortion: principalPortion,
      date: repayDate,
    ));
    _debtor.repayments.sort((a, b) => b.date.compareTo(a.date));
    await _saveAndNotify();
  }

  void _deductInterest(double amount) {
    double remaining = amount;
    _debtor.interestEntries.sort((a, b) => a.date.compareTo(b.date));
    final toRemove = <InterestEntry>[];
    for (final entry in _debtor.interestEntries) {
      if (remaining <= 0) break;
      if (entry.amount <= remaining) {
        remaining -= entry.amount;
        toRemove.add(entry);
      } else {
        final i = _debtor.interestEntries.indexOf(entry);
        _debtor.interestEntries[i] = InterestEntry(
          id: entry.id,
          amount: entry.amount - remaining,
          description: entry.description,
          date: entry.date,
        );
        remaining = 0;
      }
    }
    for (final e in toRemove) {
      _debtor.interestEntries.remove(e);
    }
  }

  Future<void> _addManualInterest() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const RepaymentEditor(
        title: '手动加息',
        label: '加息金额',
        buttonText: '确认加息',
      ),
    );
    if (result == null) return;
    _debtor.interestEntries.add(InterestEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      amount: result['amount'] as double,
      description: '手动加息',
      date: result['date'] as DateTime,
    ));
    await _saveAndNotify();
  }

  Future<void> _deleteTimelineEntry(String id) async {
    bool found = false;
    final repIdx = _debtor.repayments.indexWhere((r) => r.id == id);
    if (repIdx >= 0) {
      final r = _debtor.repayments[repIdx];
      final ok = await _confirmDelete(
        '确认删除 ${formatDate(r.date)} 的 ${money(r.amount)} 还款吗？',
      );
      if (ok != true) return;
      _debtor.repayments.removeAt(repIdx);
      found = true;
    } else {
      final intIdx = _debtor.interestEntries.indexWhere((e) => e.id == id);
      if (intIdx >= 0) {
        final e = _debtor.interestEntries[intIdx];
        final ok = await _confirmDelete(
          '确认删除 ${formatDate(e.date)} 的「${e.description}」${money(e.amount)} 吗？',
        );
        if (ok != true) return;
        _debtor.interestEntries.removeAt(intIdx);
        found = true;
      }
    }
    if (found) await _saveAndNotify();
  }

  Future<bool?> _confirmDelete(String message) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除记录'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );

  // --- persistence ---

  Future<void> _saveAndNotify() async {
    final store = DebtStore();
    final all = await store.load();
    final index = all.indexWhere((d) => d.id == _debtor.id);
    if (index >= 0) {
      all[index] = _debtor;
      await store.save(all);
    }
    widget.onChanged();
    if (mounted) setState(() {});
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- UI ---

  List<_TimelineItem> _buildTimeline() {
    final items = <_TimelineItem>[];
    for (final e in _debtor.interestEntries) {
      items.add(_TimelineItem(
        date: e.date,
        amount: e.amount,
        description: e.description == '手动加息' ? '手动加息' : '产生利息',
        isInterest: true,
        isManualInterest: e.description == '手动加息',
        isRepayment: false,
      ));
    }
    for (final r in _debtor.repayments) {
      final desc = r.interestPortion > 0 && r.principalPortion > 0
          ? '还款 ${money(r.amount)}（其中 ${money(r.interestPortion)} 偿还利息，${money(r.principalPortion)} 扣减本金）'
          : r.interestPortion > 0
              ? '还款 ${money(r.amount)}（全部偿还利息）'
              : '还款 ${money(r.amount)}（全部扣减本金）';
      items.add(_TimelineItem(
        date: r.date,
        amount: r.amount,
        description: desc,
        isRepayment: true,
      ));
    }
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  String? _findItemId(int index, List<_TimelineItem> timeline) {
    final reps = List<Repayment>.from(_debtor.repayments)
      ..sort((a, b) => b.date.compareTo(a.date));
    final ints = List<InterestEntry>.from(_debtor.interestEntries)
      ..sort((a, b) => b.date.compareTo(a.date));
    int repIdx = 0, intIdx = 0, combined = 0;

    while (repIdx < reps.length || intIdx < ints.length) {
      final rDate = repIdx < reps.length ? reps[repIdx].date : null;
      final iDate = intIdx < ints.length ? ints[intIdx].date : null;
      if (rDate != null && (iDate == null || rDate.isAfter(iDate))) {
        if (combined == index) return reps[repIdx].id;
        repIdx++;
      } else if (iDate != null) {
        if (combined == index) return ints[intIdx].id;
        intIdx++;
      } else {
        break;
      }
      combined++;
    }
    return null;
  }

  static const _modeLabels = {
    InterestMode.daily: 'A 按日计息',
    InterestMode.monthly: 'B 月固定利息',
    InterestMode.manual: 'C 纯手动',
  };

  @override
  Widget build(BuildContext context) {
    final principal = _debtor.remainingPrincipal;
    final interest = _debtor.accruedInterest;
    final total = _debtor.totalRemaining;
    final cleared = principal <= 0 && interest <= 0;
    final timeline = _buildTimeline();

    return Scaffold(
      appBar: AppBar(
        title: Text(_debtor.name),
        actions: [
          Chip(
            label: Text(_modeLabels[_debtor.interestMode] ?? '',
                style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ---- Summary card ----
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(cleared ? '已全部还清 🎉' : '剩余未还总额',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    cleared ? '0.00' : money(total).replaceFirst('￥', ''),
                    style: TextStyle(
                      fontSize: cleared ? 32 : 40,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: cleared
                          ? const Color(0xff1f7a55)
                          : const Color(0xffbb3e32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: MiniStat(
                              label: '当前本金',
                              value: money(principal),
                              color: const Color(0xff287d6f))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: MiniStat(
                              label: '未结利息',
                              value: money(interest),
                              color: interest > 0
                                  ? const Color(0xffbb3e32)
                                  : const Color(0xff287d6f))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: MiniStat(
                              label: '借款总额',
                              value: money(_debtor.totalAmount),
                              color: const Color(0xff5c6b7a))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_debtor.interestMode == InterestMode.daily &&
                      _debtor.annualRate > 0)
                    Text('年利率 ${_debtor.annualRate}% · ${formatDate(_debtor.borrowDate)} 借款',
                        style: Theme.of(context).textTheme.bodySmall)
                  else if (_debtor.interestMode == InterestMode.monthly &&
                      _debtor.monthlyFixedInterest > 0)
                    Text(
                        '月固定利息 ${money(_debtor.monthlyFixedInterest)} · ${formatDate(_debtor.borrowDate)} 借款',
                        style: Theme.of(context).textTheme.bodySmall)
                  else
                    Text('${formatDate(_debtor.borrowDate)} 借款',
                        style: Theme.of(context).textTheme.bodySmall),
                  if (_debtor.lastInterestDate != null &&
                      _debtor.interestMode != InterestMode.manual)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '计息基准日期：${formatDate(_debtor.lastInterestDate!)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xff287d6f),
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // ---- Action buttons ----
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _recordRepayment,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('记录还款',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: _addManualInterest,
                      icon: const Icon(Icons.trending_up, size: 18),
                      label: const Text('调整利息',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ---- Timeline header ----
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.timeline,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('流水记录',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (timeline.isNotEmpty)
                  Text('共 ${timeline.length} 条',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // ---- Timeline list ----
          Expanded(
            child: timeline.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 8),
                        Text('暂无流水记录',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: timeline.length,
                    itemBuilder: (context, index) {
                      final item = timeline[index];
                      final isFirst = index == 0;
                      final isLast = index == timeline.length - 1;
                      final icon = item.isRepayment
                          ? Icons.payments_outlined
                          : item.isManualInterest
                              ? Icons.touch_app
                              : Icons.account_balance;
                      final iconColor = item.isRepayment
                          ? const Color(0xff1f7a55)
                          : const Color(0xffbb3e32);

                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 32,
                              child: Column(
                                children: [
                                  if (!isFirst)
                                    Expanded(
                                        child: Container(
                                            width: 2,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outlineVariant)),
                                  Container(
                                    width: 12,
                                    height: 12,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: item.isRepayment
                                          ? const Color(0xff1f7a55)
                                          : const Color(0xffbb3e32),
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                        child: Container(
                                            width: 2,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outlineVariant)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon, size: 20, color: iconColor),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(formatDate(item.date),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                        color: Theme.of(
                                                                context)
                                                            .colorScheme
                                                            .outline)),
                                            const SizedBox(height: 2),
                                            Text(item.description,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        item.isRepayment
                                            ? '-${money(item.amount)}'
                                            : '+${money(item.amount)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: item.isRepayment
                                                    ? const Color(0xff1f7a55)
                                                    : const Color(0xffbb3e32)),
                                      ),
                                      const SizedBox(width: 2),
                                      GestureDetector(
                                        onTap: () {
                                          final id =
                                              _findItemId(index, timeline);
                                          if (id != null) {
                                            _deleteTimelineEntry(id);
                                          }
                                        },
                                        child: Icon(Icons.close,
                                            size: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}