import 'package:flutter/material.dart';

class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
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