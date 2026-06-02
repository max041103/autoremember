import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/debtor.dart';
import '../utils/formatters.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/number_field.dart';

class AddDebtorDialog extends StatefulWidget {
  const AddDebtorDialog({super.key, this.debtor});

  final Debtor? debtor;

  @override
  State<AddDebtorDialog> createState() => _AddDebtorDialogState();
}

class _AddDebtorDialogState extends State<AddDebtorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _monthlyCtrl;
  late DateTime _borrowDate;
  late InterestMode _mode;
  String _activeField = 'amount';

  bool get _isEditing => widget.debtor != null;

  @override
  void initState() {
    super.initState();
    final d = widget.debtor;
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _amountCtrl = TextEditingController(
      text: d == null ? '' : trimMoney(d.totalAmount),
    );
    _rateCtrl = TextEditingController(
      text: d == null || d.annualRate <= 0 ? '' : trimMoney(d.annualRate),
    );
    _monthlyCtrl = TextEditingController(
      text: d == null || d.monthlyFixedInterest <= 0
          ? ''
          : trimMoney(d.monthlyFixedInterest),
    );
    _borrowDate = d?.borrowDate ?? DateTime.now();
    _mode = d?.interestMode ?? InterestMode.daily;
  }

  String get _interestPreview {
    final principal = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (principal <= 0) return '';
    if (_mode == InterestMode.daily) {
      final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0;
      if (rate <= 0) return '';
      final daily = principal * rate / 100.0 / 365.0;
      return '每日约 ${money(daily)}，每月约 ${money(daily * 30)}，每年约 ${money(principal * rate / 100.0)}';
    }
    if (_mode == InterestMode.monthly) {
      final monthly = double.tryParse(_monthlyCtrl.text.trim()) ?? 0;
      if (monthly <= 0) return '';
      return '每月 ${money(monthly)}，每年 ${money(monthly * 12)}';
    }
    return '';
  }

  void _switchField(String field) {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() => _activeField = field);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    _monthlyCtrl.dispose();
    super.dispose();
  }

  TextEditingController _activeController() => switch (_activeField) {
        'rate' => _rateCtrl,
        'monthly' => _monthlyCtrl,
        _ => _amountCtrl,
      };

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
    if (picked != null) setState(() => _borrowDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'name': _nameCtrl.text.trim(),
      'amount': double.parse(_amountCtrl.text.trim()),
      'date': _borrowDate,
      'mode': _mode,
      'rate': double.tryParse(_rateCtrl.text.trim()) ?? 0,
      'monthly': double.tryParse(_monthlyCtrl.text.trim()) ?? 0,
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
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '债务人姓名',
                  hintText: '例如：张三',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? '请输入姓名' : null,
              ),
              const SizedBox(height: 12),
              NumberField(
                controller: _amountCtrl,
                label: '借款总金额',
                hint: '例如：10000',
                isActive: _activeField == 'amount',
                onTap: () => _switchField('amount'),
                validator: (v) {
                  final amt = double.tryParse(v?.trim() ?? '');
                  return (amt == null || amt <= 0) ? '请输入有效金额' : null;
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
                child: Text('利息模式',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              SegmentedButton<InterestMode>(
                segments: const [
                  ButtonSegment(
                      value: InterestMode.daily,
                      label: Text('A 按日计息'),
                      icon: Icon(Icons.schedule, size: 18)),
                  ButtonSegment(
                      value: InterestMode.monthly,
                      label: Text('B 月固定'),
                      icon: Icon(Icons.calendar_month, size: 18)),
                  ButtonSegment(
                      value: InterestMode.manual,
                      label: Text('C 纯手动'),
                      icon: Icon(Icons.touch_app, size: 18)),
                ],
                selected: {_mode},
                onSelectionChanged: (values) => setState(() {
                  _mode = values.first;
                  if (_mode != InterestMode.daily) _rateCtrl.clear();
                  if (_mode != InterestMode.monthly) _monthlyCtrl.clear();
                }),
              ),
              const SizedBox(height: 12),
              if (_mode == InterestMode.daily) ...[
                NumberField(
                  controller: _rateCtrl,
                  label: '年利率（%）',
                  hint: '例如：12 表示 12%',
                  suffix: '% / 年',
                  isActive: _activeField == 'rate',
                  onTap: () => _switchField('rate'),
                  validator: (v) =>
                      (double.tryParse(v?.trim() ?? '') ?? 0) <= 0
                          ? '请输入年利率'
                          : null,
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
                NumberField(
                  controller: _monthlyCtrl,
                  label: '月固定利息（￥）',
                  hint: '例如：200',
                  isActive: _activeField == 'monthly',
                  onTap: () => _switchField('monthly'),
                  validator: (v) =>
                      (double.tryParse(v?.trim() ?? '') ?? 0) <= 0
                          ? '请输入月利息金额'
                          : null,
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
              AmountKeypad(
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