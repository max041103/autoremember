import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoRememberApp());
}

// ============================================================================
// 债务追踪数据模型 —— 全面支持三种利息模式
// ============================================================================

enum InterestMode { daily, monthly, manual }

/// 利息/调息流水条目
class InterestEntry {
  InterestEntry({
    required this.id,
    required this.amount,
    required this.description,
    required this.date,
  });

  final String id;
  final double amount;
  final String description;
  final DateTime date;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'description': description,
      'date': date.toIso8601String(),
    };
  }

  factory InterestEntry.fromJson(Map<String, dynamic> json) {
    return InterestEntry(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String? ?? '',
      date:
          DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 还款记录（支持利息/本金拆分）
class Repayment {
  Repayment({
    required this.id,
    required this.amount,
    required this.interestPortion,
    required this.principalPortion,
    required this.date,
  });

  final String id;
  final double amount;
  final double interestPortion;
  final double principalPortion;
  final DateTime date;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'interestPortion': interestPortion,
      'principalPortion': principalPortion,
      'date': date.toIso8601String(),
    };
  }

  factory Repayment.fromJson(Map<String, dynamic> json) {
    return Repayment(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      interestPortion: (json['interestPortion'] as num?)?.toDouble() ?? 0,
      principalPortion: (json['principalPortion'] as num?)?.toDouble() ??
          (json['amount'] as num?)?.toDouble() ??
          0,
      date:
          DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class Debtor {
  Debtor({
    required this.id,
    required this.name,
    required this.totalAmount,
    required this.borrowDate,
    this.interestMode = InterestMode.daily,
    this.annualRate = 0.0,
    this.monthlyFixedInterest = 0.0,
    this.repayments = const [],
    this.interestEntries = const [],
    this.lastInterestDate,
  });

  final String id;
  String name;
  double totalAmount;
  DateTime borrowDate;
  InterestMode interestMode;
  double annualRate; // 模式 A：年利率 %
  double monthlyFixedInterest; // 模式 B：每月固定利息金额
  List<Repayment> repayments;
  List<InterestEntry> interestEntries;
  DateTime? lastInterestDate; // 上次计息截止日期，作为下次计息的起点

  /// 已还本金总额
  double get repaidPrincipal =>
      repayments.fold(0.0, (sum, r) => sum + r.principalPortion);

  /// 当前剩余本金
  double get remainingPrincipal => totalAmount - repaidPrincipal;

  /// 累计未结利息（所有 interestEntries 之和）
  double get accruedInterest =>
      interestEntries.fold(0.0, (sum, e) => sum + e.amount);

  /// 剩余未还总额（本金 + 利息）
  double get totalRemaining => remainingPrincipal + accruedInterest;

  double get repaidAmount =>
      repayments.fold(0.0, (sum, r) => sum + r.amount);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'totalAmount': totalAmount,
      'borrowDate': borrowDate.toIso8601String(),
      'interestMode': interestMode.name,
      'annualRate': annualRate,
      'monthlyFixedInterest': monthlyFixedInterest,
      'repayments': repayments.map((r) => r.toJson()).toList(),
      'interestEntries': interestEntries.map((e) => e.toJson()).toList(),
      if (lastInterestDate != null)
        'lastInterestDate': lastInterestDate!.toIso8601String(),
    };
  }

  factory Debtor.fromJson(Map<String, dynamic> json) {
    final modeStr = json['interestMode'] as String?;
    InterestMode mode;
    switch (modeStr) {
      case 'daily':
        mode = InterestMode.daily;
        break;
      case 'monthly':
        mode = InterestMode.monthly;
        break;
      case 'manual':
        mode = InterestMode.manual;
        break;
      default:
        mode = InterestMode.daily;
    }

    return Debtor(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? '',
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
      borrowDate: DateTime.tryParse(
            json['date'] as String? ?? json['borrowDate'] as String? ?? '',
          ) ??
          DateTime.now(),
      interestMode: mode,
      annualRate: (json['annualRate'] as num?)?.toDouble() ?? 0,
      monthlyFixedInterest:
          (json['monthlyFixedInterest'] as num?)?.toDouble() ?? 0,
      repayments: (json['repayments'] as List<dynamic>?)
              ?.map(
                  (r) => Repayment.fromJson(Map<String, dynamic>.from(r)))
              .toList() ??
          [],
      interestEntries: (json['interestEntries'] as List<dynamic>?)
              ?.map((e) =>
                  InterestEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      lastInterestDate:
          DateTime.tryParse(json['lastInterestDate'] as String? ?? ''),
    );
  }
}

class DebtStore {
  static const _key = 'debt_data';

  Future<List<Debtor>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Debtor.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Debtor> debtors) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = const JsonEncoder.withIndent('  ').convert(
      debtors.map((d) => d.toJson()).toList(),
    );
    await prefs.setString(_key, raw);
  }
}

// ============================================================================
// 利息计算工具函数
// ============================================================================

/// 模式 A：计算日利息
double calcDailyInterest(
  double principal,
  double annualRatePercent,
  DateTime startDate,
  DateTime endDate,
) {
  if (principal <= 0 || annualRatePercent <= 0) return 0;
  final days = endDate.difference(startDate).inDays;
  if (days <= 0) return 0;
  final dailyRate = annualRatePercent / 100.0 / 365.0;
  return principal * dailyRate * days;
}

/// 模式 B：计算应产生的月固定利息笔数
int calcMonthlyInterestCount(
  DateTime borrowDate,
  double monthlyAmount,
  int existingEntries,
) {
  if (monthlyAmount <= 0) return 0;
  final now = DateTime.now();
  final totalMonths =
      (now.year - borrowDate.year) * 12 + (now.month - borrowDate.month);
  if (totalMonths <= 0) return 0;
  final missing = totalMonths - existingEntries;
  return missing > 0 ? missing : 0;
}

class AutoRememberApp extends StatelessWidget {
  const AutoRememberApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff287d6f),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '债务追踪',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff7f8f5),
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: const DebtHomePage(),
    );
  }
}

// ============================================================================
// 数字键盘组件
// ============================================================================

class _AmountKeypad extends StatelessWidget {
  const _AmountKeypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0'];

    return Material(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int row = 0; row < 4; row++)
              Padding(
                padding: EdgeInsets.only(top: row == 0 ? 0 : 8),
                child: Row(
                  children: [
                    for (int col = 0; col < 3; col++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: col == 0 ? 0 : 4,
                            right: col == 2 ? 0 : 4,
                          ),
                          child: _buildKey(context, keys, row * 3 + col),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(BuildContext context, List<String> keys, int index) {
    if (index == 11) {
      return _AmountKey(
        tooltip: '删除',
        onPressed: onBackspace,
        child: const Icon(Icons.backspace_outlined),
      );
    }

    final value = keys[index];
    return _AmountKey(
      tooltip: value,
      onPressed: () => onDigit(value),
      child: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _AmountKey extends StatelessWidget {
  const _AmountKey({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.zero,
        ),
        child: child,
      ),
    );
  }
}

// ============================================================================
// 添加债务人弹窗
// ============================================================================

class _AddDebtorDialog extends StatefulWidget {
  const _AddDebtorDialog({this.debtor});

  final Debtor? debtor;

  @override
  State<_AddDebtorDialog> createState() => _AddDebtorDialogState();
}

class _AddDebtorDialogState extends State<_AddDebtorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _rateController;
  late final TextEditingController _monthlyController;

  late DateTime _borrowDate;
  late InterestMode _mode;
  String _activeField = 'amount';

  bool get _isEditing => widget.debtor != null;

  @override
  void initState() {
    super.initState();
    final d = widget.debtor;
    _nameController = TextEditingController(text: d?.name ?? '');
    _amountController = TextEditingController(
      text: d == null ? '' : trimMoney(d.totalAmount),
    );
    _rateController = TextEditingController(
      text: d == null || d.annualRate <= 0 ? '' : trimMoney(d.annualRate),
    );
    _monthlyController = TextEditingController(
      text: d == null || d.monthlyFixedInterest <= 0
          ? ''
          : trimMoney(d.monthlyFixedInterest),
    );
    _borrowDate = d?.borrowDate ?? DateTime.now();
    _mode = d?.interestMode ?? InterestMode.daily;
  }

  String get _interestPreview {
    final principal = double.tryParse(_amountController.text.trim()) ?? 0;
    if (principal <= 0) return '';

    if (_mode == InterestMode.daily) {
      final rate = double.tryParse(_rateController.text.trim()) ?? 0;
      if (rate <= 0) return '';
      final daily = principal * rate / 100.0 / 365.0;
      final monthly = daily * 30;
      final yearly = principal * rate / 100.0;
      return '每日约 ${money(daily)}，每月约 ${money(monthly)}，每年约 ${money(yearly)}';
    }

    if (_mode == InterestMode.monthly) {
      final monthly = double.tryParse(_monthlyController.text.trim()) ?? 0;
      if (monthly <= 0) return '';
      final yearly = monthly * 12;
      return '每月 ${money(monthly)}，每年 ${money(yearly)}';
    }

    return '';
  }

  void _switchField(String field) {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() => _activeField = field);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _rateController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  TextEditingController _activeController() {
    switch (_activeField) {
      case 'rate':
        return _rateController;
      case 'monthly':
        return _monthlyController;
      default:
        return _amountController;
    }
  }

  void _appendDigit(String token) {
    final ctrl = _activeController();
    final text = ctrl.text;
    if (token == '.') {
      if (text.contains('.')) return;
      _setCtrlText(ctrl, text.isEmpty ? '0.' : '$text.');
      return;
    }
    final dot = text.indexOf('.');
    if (dot >= 0 && text.length - dot > 2) return;
    if (text == '0') {
      _setCtrlText(ctrl, token == '0' ? '0' : token);
      return;
    }
    _setCtrlText(ctrl, '$text$token');
  }

  void _deleteDigit() {
    final ctrl = _activeController();
    final text = ctrl.text;
    if (text.isEmpty) return;
    _setCtrlText(ctrl, text.substring(0, text.length - 1));
  }

  void _setCtrlText(TextEditingController ctrl, String text) {
    ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _borrowDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _borrowDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'amount': double.parse(_amountController.text.trim()),
      'date': _borrowDate,
      'mode': _mode,
      'rate': double.tryParse(_rateController.text.trim()) ?? 0,
      'monthly': double.tryParse(_monthlyController.text.trim()) ?? 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? '编辑债务人' : '新增债务人'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '债务人姓名',
                  hintText: '例如：张三',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? '请输入姓名' : null,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _amountController,
                label: '借款总金额',
                hint: '例如：10000',
                isActive: _activeField == 'amount',
                onTap: () => _switchField('amount'),
                validator: (v) {
                  final amt = double.tryParse(v?.trim() ?? '');
                  if (amt == null || amt <= 0) return '请输入有效金额';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('借款日期：${formatDate(_borrowDate)}'),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '利息模式',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<InterestMode>(
                segments: const [
                  ButtonSegment(
                    value: InterestMode.daily,
                    label: Text('A 按日计息'),
                    icon: Icon(Icons.schedule, size: 18),
                  ),
                  ButtonSegment(
                    value: InterestMode.monthly,
                    label: Text('B 月固定'),
                    icon: Icon(Icons.calendar_month, size: 18),
                  ),
                  ButtonSegment(
                    value: InterestMode.manual,
                    label: Text('C 纯手动'),
                    icon: Icon(Icons.touch_app, size: 18),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (values) {
                  setState(() {
                    _mode = values.first;
                    if (_mode != InterestMode.daily) {
                      _rateController.clear();
                    }
                    if (_mode != InterestMode.monthly) {
                      _monthlyController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_mode == InterestMode.daily) ...[
                _NumberField(
                  controller: _rateController,
                  label: '年利率（%）',
                  hint: '例如：12 表示 12%',
                  suffix: '% / 年',
                  isActive: _activeField == 'rate',
                  onTap: () => _switchField('rate'),
                  validator: (v) {
                    final r = double.tryParse(v?.trim() ?? '');
                    if (r == null || r <= 0) return '请输入年利率';
                    return null;
                  },
                ),
                if (_interestPreview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _interestPreview,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xff287d6f),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
              if (_mode == InterestMode.monthly) ...[
                _NumberField(
                  controller: _monthlyController,
                  label: '月固定利息（￥）',
                  hint: '例如：200',
                  isActive: _activeField == 'monthly',
                  onTap: () => _switchField('monthly'),
                  validator: (v) {
                    final m = double.tryParse(v?.trim() ?? '');
                    if (m == null || m <= 0) return '请输入月利息金额';
                    return null;
                  },
                ),
                if (_interestPreview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _interestPreview,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xff287d6f),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
              if (_mode == InterestMode.manual)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '模式 C：添加后可在详情页手动调整利息',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              const SizedBox(height: 8),
              _AmountKeypad(
                onDigit: _appendDigit,
                onBackspace: _deleteDigit,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }
}

/// 数字输入字段：只读 + 点击切换键盘焦点
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.isActive,
    required this.onTap,
    required this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isActive;
  final VoidCallback onTap;
  final FormFieldValidator<String> validator;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = isActive ? cs.primary : cs.outline;
    return GestureDetector(
      onTap: onTap,
      child: AbsorbPointer(
        child: TextFormField(
          controller: controller,
          readOnly: true,
          showCursor: isActive,
          keyboardType: TextInputType.none,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixText: '￥ ',
            suffixText: suffix,
            border:
                OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            enabledBorder:
                OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
            focusedBorder: OutlineInputBorder(
              borderSide:
                  BorderSide(color: borderColor, width: isActive ? 2 : 1),
            ),
            disabledBorder:
                OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
          ),
          validator: validator,
        ),
      ),
    );
  }
}

// ============================================================================
// 债务追踪看板主页
// ============================================================================

class DebtHomePage extends StatefulWidget {
  const DebtHomePage({super.key});

  @override
  State<DebtHomePage> createState() => _DebtHomePageState();
}

class _DebtHomePageState extends State<DebtHomePage> {
  final DebtStore _debtStore = DebtStore();
  List<Debtor> _debtors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final debtors = await _debtStore.load();
    if (!mounted) return;
    setState(() {
      _debtors = debtors;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _debtStore.save(_debtors);
    if (mounted) setState(() {});
  }

  Future<void> _deleteDebtor(Debtor debtor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除债务人'),
        content: Text('确认删除「${debtor.name}」及其所有还款和利息记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
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
      builder: (_) => const _AddDebtorDialog(),
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
      builder: (_) => _AddDebtorDialog(debtor: debtor),
    );

    if (result == null) return;

    setState(() {
      debtor.name = result['name'] as String;
      debtor.totalAmount = result['amount'] as double;
      debtor.borrowDate = result['date'] as DateTime;
      debtor.interestMode = result['mode'] as InterestMode;
      debtor.annualRate = result['rate'] as double;
      debtor.monthlyFixedInterest = result['monthly'] as double;
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '还没有债务人',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '点右下角添加欠你钱的人',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
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
                                backgroundColor: isCleared
                                    ? const Color(0xff1f7a55)
                                        .withValues(alpha: 0.12)
                                    : const Color(0xffbb3e32)
                                        .withValues(alpha: 0.12),
                                foregroundColor: isCleared
                                    ? const Color(0xff1f7a55)
                                    : const Color(0xffbb3e32),
                                child: Text(
                                  debtor.name.isNotEmpty
                                      ? debtor.name[0]
                                      : '?',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
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
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '借款 ${formatDate(debtor.borrowDate)} · 共 ${money(debtor.totalAmount)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    if (debtor.accruedInterest > 0)
                                      Text(
                                        '未结利息 ${money(debtor.accruedInterest)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  const Color(0xffbb3e32),
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isCleared ? '已还清' : '待还',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
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
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editDebtor(debtor);
                                  } else if (value == 'delete') {
                                    _deleteDebtor(debtor);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                      value: 'edit',
                                      child: Text('编辑债务人')),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除债务人')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ============================================================================
// 债务人详情页
// ============================================================================

class _TimelineItem {
  const _TimelineItem({
    required this.date,
    required this.label,
    required this.amount,
    required this.description,
    this.isInterest = false,
    this.isManualInterest = false,
    this.isRepayment = true,
  });

  final DateTime date;
  final String label;
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
    final now = DateTime.now();
    bool changed = false;

    // 确定计息起点：优先使用 lastInterestDate，退化到 borrowDate
    final interestBaseDate = _debtor.lastInterestDate ?? _debtor.borrowDate;

    if (_debtor.interestMode == InterestMode.daily &&
        _debtor.annualRate > 0 &&
        _debtor.remainingPrincipal > 0) {
      // 模式 A：从 interestBaseDate 逐日计算到 now
      DateTime cursor = interestBaseDate;
      while (cursor.isBefore(now)) {
        final nextDate = cursor.add(const Duration(days: 1));
        if (nextDate.isAfter(now)) break;
        final interest = calcDailyInterest(
          _debtor.remainingPrincipal,
          _debtor.annualRate,
          cursor,
          nextDate,
        );
        if (interest > 0) {
          _debtor.interestEntries.add(InterestEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            amount: interest,
            description: '按日计息（${_debtor.annualRate}%年利率）',
            date: nextDate,
          ));
          changed = true;
        }
        cursor = nextDate;
      }
      // 状态展期：推进计息基准日期到 cursor
      if (cursor.isAfter(interestBaseDate)) {
        _debtor.lastInterestDate = cursor;
        changed = true;
      }
    } else if (_debtor.interestMode == InterestMode.monthly &&
        _debtor.monthlyFixedInterest > 0 &&
        _debtor.remainingPrincipal > 0) {
      // 模式 B：从 interestBaseDate 逐月生成利息，直到超过 now
      DateTime cursor = interestBaseDate;
      DateTime? lastGeneratedDate;
      while (true) {
        // 计算下一个月的同一天
        final nextMonth = DateTime(cursor.year, cursor.month + 1, cursor.day);
        // 处理月末日期溢出（如 1月31日 → 2月28日）
        DateTime dueDate;
        if (nextMonth.day == cursor.day) {
          dueDate = nextMonth;
        } else {
          // 日期溢出，使用该月最后一天
          dueDate = DateTime(cursor.year, cursor.month + 2, 0);
        }

        if (dueDate.isAfter(now)) break;

        _debtor.interestEntries.add(InterestEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          amount: _debtor.monthlyFixedInterest,
          description: '月固定利息 ${money(_debtor.monthlyFixedInterest)}',
          date: dueDate,
        ));
        lastGeneratedDate = dueDate;
        changed = true;
        cursor = dueDate;
      }
      // 状态展期：推进计息基准日期到最后一次生成利息的日期
      if (lastGeneratedDate != null &&
          lastGeneratedDate.isAfter(interestBaseDate)) {
        _debtor.lastInterestDate = lastGeneratedDate;
        changed = true;
      }
    }

    if (changed) {
      await _saveAndNotify();
    }
  }

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
      builder: (_) => const _RepaymentEditor(),
    );

    if (result == null) return;

    final totalAmount = result['amount'] as double;
    final repayDate = result['date'] as DateTime;

    final currentInterest = _debtor.accruedInterest;
    double interestPortion;
    double principalPortion;

    if (totalAmount <= currentInterest) {
      interestPortion = totalAmount;
      principalPortion = 0;
      _deductInterest(totalAmount);
    } else {
      interestPortion = currentInterest;
      principalPortion = totalAmount - currentInterest;
      _debtor.interestEntries.clear();
    }

    final repayment = Repayment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      amount: totalAmount,
      interestPortion: interestPortion,
      principalPortion: principalPortion,
      date: repayDate,
    );

    setState(() {
      _debtor.repayments.add(repayment);
      _debtor.repayments.sort((a, b) => b.date.compareTo(a.date));
    });
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
        final index = _debtor.interestEntries.indexOf(entry);
        _debtor.interestEntries[index] = InterestEntry(
          id: entry.id,
          amount: entry.amount - remaining,
          description: entry.description,
          date: entry.date,
        );
        remaining = 0;
      }
    }
    for (final entry in toRemove) {
      _debtor.interestEntries.remove(entry);
    }
  }

  Future<void> _addManualInterest() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _RepaymentEditor(
        title: '手动加息',
        label: '加息金额',
        buttonText: '确认加息',
      ),
    );

    if (result == null) return;

    final amount = result['amount'] as double;
    final date = result['date'] as DateTime;

    setState(() {
      _debtor.interestEntries.add(InterestEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        amount: amount,
        description: '手动加息',
        date: date,
      ));
    });
    await _saveAndNotify();
  }

  Future<void> _deleteTimelineEntry(String id) async {
    bool found = false;
    final repIndex = _debtor.repayments.indexWhere((r) => r.id == id);
    if (repIndex >= 0) {
      final repayment = _debtor.repayments[repIndex];
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除记录'),
          content: Text(
              '确认删除 ${formatDate(repayment.date)} 的 ${money(repayment.amount)} 还款吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() {
        _debtor.repayments.removeAt(repIndex);
      });
      found = true;
    } else {
      final intIndex =
          _debtor.interestEntries.indexWhere((e) => e.id == id);
      if (intIndex >= 0) {
        final entry = _debtor.interestEntries[intIndex];
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除记录'),
            content: Text(
                '确认删除 ${formatDate(entry.date)} 的「${entry.description}」${money(entry.amount)} 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        setState(() {
          _debtor.interestEntries.removeAt(intIndex);
        });
        found = true;
      }
    }
    if (found) await _saveAndNotify();
  }

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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final remainingPrincipal = _debtor.remainingPrincipal;
    final accruedInterest = _debtor.accruedInterest;
    final totalRemaining = _debtor.totalRemaining;
    final isCleared = remainingPrincipal <= 0 && accruedInterest <= 0;

    final timeline = <_TimelineItem>[];

    for (final entry in _debtor.interestEntries) {
      timeline.add(_TimelineItem(
        date: entry.date,
        label: entry.description,
        amount: entry.amount,
        description:
            entry.description == '手动加息' ? '手动加息' : '产生利息',
        isInterest: true,
        isManualInterest: entry.description == '手动加息',
        isRepayment: false,
      ));
    }

    for (final repayment in _debtor.repayments) {
      String desc;
      if (repayment.interestPortion > 0 && repayment.principalPortion > 0) {
        desc =
            '还款 ${money(repayment.amount)}（其中 ${money(repayment.interestPortion)} 偿还利息，${money(repayment.principalPortion)} 扣减本金）';
      } else if (repayment.interestPortion > 0) {
        desc = '还款 ${money(repayment.amount)}（全部偿还利息）';
      } else {
        desc = '还款 ${money(repayment.amount)}（全部扣减本金）';
      }
      timeline.add(_TimelineItem(
        date: repayment.date,
        label: '还款',
        amount: repayment.amount,
        description: desc,
        isRepayment: true,
      ));
    }

    timeline.sort((a, b) => b.date.compareTo(a.date));

    final modeLabels = {
      InterestMode.daily: 'A 按日计息',
      InterestMode.monthly: 'B 月固定利息',
      InterestMode.manual: 'C 纯手动',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_debtor.name),
        actions: [
          Chip(
            label: Text(
              modeLabels[_debtor.interestMode] ?? '',
              style: const TextStyle(fontSize: 12),
            ),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    isCleared ? '已全部还清 🎉' : '剩余未还总额',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isCleared
                        ? '0.00'
                        : money(totalRemaining).replaceFirst('￥', ''),
                    style: TextStyle(
                      fontSize: isCleared ? 32 : 40,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: isCleared
                          ? const Color(0xff1f7a55)
                          : const Color(0xffbb3e32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          label: '当前本金',
                          value: money(remainingPrincipal),
                          color: const Color(0xff287d6f),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniStat(
                          label: '未结利息',
                          value: money(accruedInterest),
                          color: accruedInterest > 0
                              ? const Color(0xffbb3e32)
                              : const Color(0xff287d6f),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniStat(
                          label: '借款总额',
                          value: money(_debtor.totalAmount),
                          color: const Color(0xff5c6b7a),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_debtor.interestMode == InterestMode.daily &&
                      _debtor.annualRate > 0)
                    Text(
                      '年利率 ${_debtor.annualRate}% · ${formatDate(_debtor.borrowDate)} 借款',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else if (_debtor.interestMode == InterestMode.monthly &&
                      _debtor.monthlyFixedInterest > 0)
                    Text(
                      '月固定利息 ${money(_debtor.monthlyFixedInterest)} · ${formatDate(_debtor.borrowDate)} 借款',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    Text(
                      '${formatDate(_debtor.borrowDate)} 借款',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
                      label:
                          const Text('记录还款', style: TextStyle(fontSize: 14)),
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
                      label:
                          const Text('调整利息', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.timeline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '流水记录',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (timeline.isNotEmpty)
                  Text(
                    '共 ${timeline.length} 条',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: timeline.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '暂无流水记录',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
                          : (item.isManualInterest
                              ? Icons.touch_app
                              : Icons.account_balance);

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
                                            .outlineVariant,
                                      ),
                                    ),
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
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                      ),
                                    ),
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
                                      Icon(
                                        icon,
                                        size: 20,
                                        color: iconColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              formatDate(item.date),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .outline,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item.description,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
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
                                                  : const Color(0xffbb3e32),
                                            ),
                                      ),
                                      const SizedBox(width: 2),
                                      GestureDetector(
                                        onTap: () {
                                          final itemId =
                                              _findItemId(index, item);
                                          if (itemId != null) {
                                            _deleteTimelineEntry(itemId);
                                          }
                                        },
                                        child: Icon(
                                          Icons.close,
                                          size: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
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

  String? _findItemId(int index, _TimelineItem item) {
    final allRepayments = List<Repayment>.from(_debtor.repayments)
      ..sort((a, b) => b.date.compareTo(a.date));
    final allInterest = List<InterestEntry>.from(_debtor.interestEntries)
      ..sort((a, b) => b.date.compareTo(a.date));

    int repIdx = 0;
    int intIdx = 0;
    int combinedIdx = 0;

    while (repIdx < allRepayments.length || intIdx < allInterest.length) {
      final repDate = repIdx < allRepayments.length
          ? allRepayments[repIdx].date
          : null;
      final intDate =
          intIdx < allInterest.length ? allInterest[intIdx].date : null;

      if (repDate != null && (intDate == null || repDate.isAfter(intDate))) {
        if (combinedIdx == index) return allRepayments[repIdx].id;
        repIdx++;
      } else if (intDate != null) {
        if (combinedIdx == index) return allInterest[intIdx].id;
        intIdx++;
      } else {
        break;
      }
      combinedIdx++;
    }
    return null;
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 还款/调息编辑器
// ============================================================================

class _RepaymentEditor extends StatefulWidget {
  const _RepaymentEditor({
    this.title = '记录还款',
    this.label = '还款金额',
    this.buttonText = '确认还款',
  });

  final String title;
  final String label;
  final String buttonText;

  @override
  State<_RepaymentEditor> createState() => _RepaymentEditorState();
}

class _RepaymentEditorState extends State<_RepaymentEditor> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  void _appendAmountToken(String token) {
    final text = _amountController.text;

    if (token == '.') {
      if (text.contains('.')) return;
      _setAmountText(text.isEmpty ? '0.' : '$text.');
      return;
    }

    final decimalIndex = text.indexOf('.');
    if (decimalIndex >= 0 && text.length - decimalIndex > 2) return;

    if (text == '0') {
      _setAmountText(token == '0' ? '0' : token);
      return;
    }

    _setAmountText('$text$token');
  }

  void _deleteAmountToken() {
    final text = _amountController.text;
    if (text.isEmpty) return;
    _setAmountText(text.substring(0, text.length - 1));
  }

  void _setAmountText(String text) {
    _amountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text.trim());
    Navigator.pop(context, {'amount': amount, 'date': _date});
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.92;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        readOnly: true,
                        showCursor: true,
                        keyboardType: TextInputType.none,
                        decoration: InputDecoration(
                          prefixText: '￥ ',
                          labelText: widget.label,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final amount =
                              double.tryParse(value?.trim() ?? '');
                          if (amount == null || amount <= 0) {
                            return '请输入大于 0 的金额';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(formatDate(_date)),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: Text(widget.buttonText),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              _AmountKeypad(
                onDigit: _appendAmountToken,
                onBackspace: _deleteAmountToken,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 工具函数
// ============================================================================

String money(double value) => '￥${value.toStringAsFixed(2)}';

String trimMoney(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}

String formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}