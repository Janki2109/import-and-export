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

// PendingWithdrawalsTotal — sum of this user's not-yet-processed withdrawal requests. Since
// the ledger isn't debited until admin approval (CreateWithdrawalRequest), this has to be
// subtracted from the raw ledger balance to get what's actually still available to withdraw —
// otherwise a user could submit several withdrawal requests exceeding their real balance
// before any of them are approved.
func (r *WalletRepository) PendingWithdrawalsTotal(ctx context.Context, userID string) (float64, error) {
	var total float64
	err := r.db.QueryRow(ctx, `SELECT COALESCE(SUM(amount), 0) FROM withdrawal_requests WHERE user_id = $1 AND status = 'pending'`, userID).Scan(&total)
	return total, err
}

// CreateWithdrawalRequest — records the request only; no ledger effect until an admin approves
// it (see AdminRepository.MarkWithdrawalPaid), which is what makes it genuinely "pending".
func (r *WalletRepository) CreateWithdrawalRequest(ctx context.Context, userID string, amount float64) (*models.WithdrawalRequest, error) {
	wr := &models.WithdrawalRequest{UserID: userID, Amount: amount, Status: "pending"}
	err := r.db.QueryRow(ctx, `
		INSERT INTO withdrawal_requests (user_id, amount) VALUES ($1, $2)
		RETURNING id, status, created_at`,
		userID, amount).Scan(&wr.ID, &wr.Status, &wr.CreatedAt)
	if err != nil {
		return nil, err
	}
	return wr, nil
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
