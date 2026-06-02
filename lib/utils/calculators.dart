import '../models/debtor.dart' show Debtor, InterestEntry, InterestMode;
import 'formatters.dart' show money;
import 'package:flutter/material.dart' show DateTime;

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

/// 模式 B：计算应产生的月固定利息笔数（保留兼容旧逻辑）
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

/// 利息结算核心：根据 lastInterestDate 逐日/逐月推进，返回是否有变更
bool settleInterest(Debtor debtor) {
  final now = DateTime.now();
  bool changed = false;
  final baseDate = debtor.lastInterestDate ?? debtor.borrowDate;

  if (debtor.interestMode == InterestMode.daily &&
      debtor.annualRate > 0 &&
      debtor.remainingPrincipal > 0) {
    DateTime cursor = baseDate;
    while (cursor.isBefore(now)) {
      final nextDate = cursor.add(const Duration(days: 1));
      if (nextDate.isAfter(now)) break;
      final interest = calcDailyInterest(
        debtor.remainingPrincipal,
        debtor.annualRate,
        cursor,
        nextDate,
      );
      if (interest > 0) {
        debtor.interestEntries.add(InterestEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          amount: interest,
          description: '按日计息（${debtor.annualRate}%年利率）',
          date: nextDate,
        ));
        changed = true;
      }
      cursor = nextDate;
    }
    if (cursor.isAfter(baseDate)) {
      debtor.lastInterestDate = cursor;
      changed = true;
    }
  } else if (debtor.interestMode == InterestMode.monthly &&
      debtor.monthlyFixedInterest > 0 &&
      debtor.remainingPrincipal > 0) {
    DateTime cursor = baseDate;
    DateTime? lastDate;
    while (true) {
      final nextMonth = DateTime(cursor.year, cursor.month + 1, cursor.day);
      final dueDate = nextMonth.day == cursor.day
          ? nextMonth
          : DateTime(cursor.year, cursor.month + 2, 0);
      if (dueDate.isAfter(now)) break;
      debtor.interestEntries.add(InterestEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        amount: debtor.monthlyFixedInterest,
        description: '月固定利息 ${money(debtor.monthlyFixedInterest)}',
        date: dueDate,
      ));
      lastDate = dueDate;
      changed = true;
      cursor = dueDate;
    }
    if (lastDate != null && lastDate.isAfter(baseDate)) {
      debtor.lastInterestDate = lastDate;
      changed = true;
    }
  }

  return changed;
}