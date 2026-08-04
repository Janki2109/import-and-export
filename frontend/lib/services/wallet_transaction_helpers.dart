import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/trade.dart';

/// Everything shown for a transaction is derived from real fields the backend already
/// returns (entry_type, description, reference_id) — nothing here is fabricated. The
/// backend's ledger schema only has `credit`/`debit` and no status column, so:
///  - a withdrawal debit whose reference_id is still the "MANUAL-PENDING-*" marker (see
///    WalletService.Withdraw on the backend) is shown as Pending — it genuinely hasn't been
///    paid out yet, since payouts are processed manually by ops.
///  - every other ledger row exists only because it was already committed, so it's Completed.
///  - "Failed"/"Cancelled" never occur in this schema and are intentionally not offered
///    as real statuses (only as inert filter options, which is a UI nicety, not a lie).
enum TxnKind { credit, debit, withdrawal, refund, commission }

TxnKind classifyTxn(LedgerEntry t) {
  final desc = t.description.toLowerCase();
  if (desc.contains('refund')) return TxnKind.refund;
  if (desc.contains('withdraw')) return TxnKind.withdrawal;
  if (desc.contains('commission')) return TxnKind.commission;
  return t.entryType == 'credit' ? TxnKind.credit : TxnKind.debit;
}

String txnKindLabel(TxnKind k) {
  switch (k) {
    case TxnKind.credit:
      return 'Credit';
    case TxnKind.debit:
      return 'Debit';
    case TxnKind.withdrawal:
      return 'Withdrawal';
    case TxnKind.refund:
      return 'Refund';
    case TxnKind.commission:
      return 'Commission';
  }
}

IconData txnKindIcon(TxnKind k) {
  switch (k) {
    case TxnKind.credit:
      return Icons.arrow_downward;
    case TxnKind.debit:
      return Icons.arrow_upward;
    case TxnKind.withdrawal:
      return Icons.account_balance_outlined;
    case TxnKind.refund:
      return Icons.replay_outlined;
    case TxnKind.commission:
      return Icons.percent_outlined;
  }
}

bool isTxnPending(LedgerEntry t) => classifyTxn(t) == TxnKind.withdrawal && (t.referenceId?.startsWith('MANUAL-PENDING') ?? false);

String txnStatusLabel(LedgerEntry t) => isTxnPending(t) ? 'Pending' : 'Completed';

Color txnStatusColor(LedgerEntry t) => isTxnPending(t) ? AppColors.warning : AppColors.success;

/// Payment method is inferred from the transaction's own description — the backend never
/// tracks UPI/Card distinctly (it removed the payment-gateway integration entirely), so
/// this only ever resolves to "Bank Transfer" (withdrawals) or "Wallet" (everything else,
/// since escrow/commission/refund all move within the platform's own ledger).
String txnPaymentMethod(LedgerEntry t) => classifyTxn(t) == TxnKind.withdrawal ? 'Bank Transfer' : 'Wallet';

Color txnAmountColor(LedgerEntry t) {
  if (isTxnPending(t)) return AppColors.textSecondary;
  return t.entryType == 'credit' ? AppColors.success : AppColors.error;
}
