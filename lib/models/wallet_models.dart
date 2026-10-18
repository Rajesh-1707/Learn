import 'package:flutter/material.dart';

/// A wallet row from public.wallets.
class WalletRow {
  final String userId;
  final int balancePaise;
  final int earningsPaise;
  final String? updatedAt;

  const WalletRow({
    required this.userId,
    required this.balancePaise,
    required this.earningsPaise,
    this.updatedAt,
  });

  factory WalletRow.fromJson(Map<String, dynamic> json) {
    return WalletRow(
      userId: '${json['user_id'] ?? ''}',
      balancePaise: (json['balance_paise'] as num?)?.toInt() ?? 0,
      earningsPaise: (json['earnings_paise'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] as String?,
    );
  }
}

/// A transaction row from public.transactions.
class TransactionRow {
  final String id;
  final String userId;
  final String type;
  final int amountPaise;
  final String? ref;
  final String? note;
  final String? createdAt;

  const TransactionRow({
    required this.id,
    required this.userId,
    required this.type,
    required this.amountPaise,
    this.ref,
    this.note,
    this.createdAt,
  });

  factory TransactionRow.fromJson(Map<String, dynamic> json) {
    return TransactionRow(
      id: '${json['id'] ?? ''}',
      userId: '${json['user_id'] ?? ''}',
      type: '${json['type'] ?? ''}',
      amountPaise: (json['amount_paise'] as num?)?.toInt() ?? 0,
      ref: json['ref'] as String?,
      note: json['note'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  /// Display label per type.
  String get typeLabel {
    switch (type) {
      case 'topup':
        return 'Added money';
      case 'call_fee':
        return 'Call payment';
      case 'call_earning':
        return 'Call earning';
      case 'payout':
        return 'Withdrawal';
      case 'refund':
        return 'Refund';
      case 'ad_income':
        return 'Ad income';
      default:
        return type;
    }
  }

  /// Icon per type.
  IconData get typeIcon {
    switch (type) {
      case 'topup':
        return Icons.add_circle_outline;
      case 'call_fee':
        return Icons.phone;
      case 'call_earning':
        return Icons.attach_money;
      case 'payout':
        return Icons.upload;
      case 'refund':
        return Icons.restore;
      case 'ad_income':
        return Icons.video_label;
      default:
        return Icons.receipt;
    }
  }

  /// Whether the amount is positive (green) for this type.
  bool get isPositive {
    switch (type) {
      case 'topup':
      case 'call_earning':
      case 'refund':
        return true;
      case 'call_fee':
      case 'payout':
      case 'ad_income':
        return false;
      default:
        return true;
    }
  }
}
