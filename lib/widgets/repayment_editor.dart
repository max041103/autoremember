import 'package:flutter/material.dart';

import 'amount_keypad.dart';
import '../utils/formatters.dart' show formatDate;

class RepaymentEditor extends StatefulWidget {
  const RepaymentEditor({
    super.key,
    this.title = '记录还款',
    this.label = '还款金额',
    this.buttonText = '确认还款',
  });

  final String title;
  final String label;
  final String buttonText;

  @override
  State<RepaymentEditor> createState() => _RepaymentEditorState();
}

class _RepaymentEditorState extends State<RepaymentEditor> {
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
    if (picked != null) setState(() => _date = picked);
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
                        validator: (value) =>
                            ((double.tryParse(value?.trim() ?? '') ?? 0) <= 0)
                                ? '请输入大于 0 的金额'
                                : null,
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
              AmountKeypad(
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