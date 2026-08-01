package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type WalletRepository struct {
	db *pgxpool.Pool
}

func NewWalletRepository(db *pgxpool.Pool) *WalletRepository {
	return &WalletRepository{db: db}
}

// Balance sums the user's ledger_entries (credit - debit). No separate wallets table needed —
// ledger_entries is the source of truth (append-only, auditable).
func (r *WalletRepository) Balance(ctx context.Context, userID string) (float64, error) {
	var balance float64
	query := `SELECT COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END), 0)
		FROM ledger_entries WHERE user_id = $1`
	if err := r.db.QueryRow(ctx, query, userID).Scan(&balance); err != nil {
		return 0, err
	}
	return balance, nil
}

// RecordWithdrawal — debits the wallet after a successful Razorpay payout to the user's
// linked bank/UPI fund account.
func (r *WalletRepository) RecordWithdrawal(ctx context.Context, userID string, amount float64, razorpayPayoutID string) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO ledger_entries (user_id, entry_type, amount, description, reference_id)
		VALUES ($1, 'debit', $2, 'Withdrawal to bank account', $3)`,
		userID, amount, razorpayPayoutID)
	return err
}

func (r *WalletRepository) Transactions(ctx context.Context, userID string, limit, offset int) ([]models.LedgerEntry, error) {
	query := `SELECT id, order_id, user_id, entry_type, amount, balance_after, description, reference_id, created_at
		FROM ledger_entries WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.LedgerEntry
	for rows.Next() {
		var e models.LedgerEntry
		if err := rows.Scan(&e.ID, &e.OrderID, &e.UserID, &e.EntryType, &e.Amount, &e.BalanceAfter, &e.Description, &e.ReferenceID, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, nil
}
