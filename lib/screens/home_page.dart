import 'package:flutter/material.dart';

import '../models/debtor.dart';
import '../utils/formatters.dart';
import 'add_debtor_dialog.dart';
import 'debtor_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DebtStore _store = DebtStore();
  List<Debtor> _debtors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final debtors = await _store.load();
    if (!mounted) return;
    setState(() {
      _debtors = debtors;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _store.save(_debtors);
    if (mounted) setState(() {});
  }

  Future<void> _deleteDebtor(Debtor debtor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除债务人'),
        content: Text('确认删除「${debtor.name}」及其所有还款和利息记录吗？'),
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
    if (confirmed != true) return;
    _debtors.removeWhere((d) => d.id == debtor.id);
    await _save();
  }

  Future<void> _addDebtor() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const AddDebtorDialog(),
    );
    if (result == null) return;
    _debtors.add(Debtor(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: result['name'] as String,
      totalAmount: result['amount'] as double,
      borrowDate: result['date'] as DateTime,
      interestMode: result['mode'] as InterestMode,
      annualRate: result['rate'] as double,
      monthlyFixedInterest: result['monthly'] as double,
    ));
    await _save();
  }

  Future<void> _editDebtor(Debtor debtor) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddDebtorDialog(debtor: debtor),
    );
    if (result == null) return;
    setState(() {
      debtor
        ..name = result['name'] as String
        ..totalAmount = result['amount'] as double
        ..borrowDate = result['date'] as DateTime
        ..interestMode = result['mode'] as InterestMode
        ..annualRate = result['rate'] as double
        ..monthlyFixedInterest = result['monthly'] as double;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('债务追踪'),
        actions: [
          IconButton(
            tooltip: '添加债务人',
            onPressed: _addDebtor,
            icon: const Icon(Icons.person_add_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDebtor,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('添加债务人'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _debtors.isEmpty
              ? _buildEmpty(context)
              : _buildList(context),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('还没有债务人', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('点右下角添加欠你钱的人',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _debtors.length,
      itemBuilder: (context, index) {
        final debtor = _debtors[index];
        final remaining = debtor.totalRemaining;
        final isCleared = remaining <= 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DebtorDetailPage(
                  debtor: debtor,
                  onChanged: () => _save(),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: (isCleared
                            ? const Color(0xff1f7a55)
                            : const Color(0xffbb3e32))
                        .withValues(alpha: 0.12),
                    foregroundColor: isCleared
                        ? const Color(0xff1f7a55)
                        : const Color(0xffbb3e32),
                    child: Text(
                      debtor.name.isNotEmpty ? debtor.name[0] : '?',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          debtor.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '借款 ${formatDate(debtor.borrowDate)} · 共 ${money(debtor.totalAmount)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (debtor.accruedInterest > 0)
                          Text(
                            '未结利息 ${money(debtor.accruedInterest)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xffbb3e32)),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isCleared ? '已还清' : '待还',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        isCleared ? '✓' : money(remaining),
                        style: TextStyle(
                          fontSize: isCleared ? 16 : 18,
                          fontWeight: FontWeight.w800,
                          color: isCleared
                              ? const Color(0xff1f7a55)
                              : const Color(0xffbb3e32),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    onSelected: (value) => switch (value) {
                      'edit' => _editDebtor(debtor),
                      'delete' => _deleteDebtor(debtor),
                      _ => null,
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑债务人')),
                      PopupMenuItem(value: 'delete', child: Text('删除债务人')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}