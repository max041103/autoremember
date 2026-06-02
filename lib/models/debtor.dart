import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'description': description,
        'date': date.toIso8601String(),
      };

  factory InterestEntry.fromJson(Map<String, dynamic> json) => InterestEntry(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
      );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'interestPortion': interestPortion,
        'principalPortion': principalPortion,
        'date': date.toIso8601String(),
      };

  factory Repayment.fromJson(Map<String, dynamic> json) => Repayment(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        interestPortion: (json['interestPortion'] as num?)?.toDouble() ?? 0,
        principalPortion: (json['principalPortion'] as num?)?.toDouble() ??
            (json['amount'] as num?)?.toDouble() ??
            0,
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
      );
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
  double annualRate;
  double monthlyFixedInterest;
  List<Repayment> repayments;
  List<InterestEntry> interestEntries;
  DateTime? lastInterestDate;

  double get repaidPrincipal =>
      repayments.fold(0.0, (sum, r) => sum + r.principalPortion);
  double get remainingPrincipal => totalAmount - repaidPrincipal;
  double get accruedInterest =>
      interestEntries.fold(0.0, (sum, e) => sum + e.amount);
  double get totalRemaining => remainingPrincipal + accruedInterest;
  double get repaidAmount =>
      repayments.fold(0.0, (sum, r) => sum + r.amount);

  Map<String, dynamic> toJson() => {
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

  factory Debtor.fromJson(Map<String, dynamic> json) {
    final modeStr = json['interestMode'] as String?;
    final mode = switch (modeStr) {
      'daily' => InterestMode.daily,
      'monthly' => InterestMode.monthly,
      'manual' => InterestMode.manual,
      _ => InterestMode.daily,
    };

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
              ?.map((r) => Repayment.fromJson(Map<String, dynamic>.from(r)))
              .toList() ??
          [],
      interestEntries: (json['interestEntries'] as List<dynamic>?)
              ?.map(
                  (e) => InterestEntry.fromJson(Map<String, dynamic>.from(e)))
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