package repository

import (
	"context"
	"fmt"

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

// CreateWithdrawalRequestIfSufficientBalance — SECURITY/RACE FIX (C-06): previously Balance(),
// PendingWithdrawalsTotal(), the available-balance subtraction, and CreateWithdrawalRequest()
// were four separate pool queries with no transaction, no row lock, and no unique guard — two
// concurrent withdrawal requests for the same user could both read the same balance/pending
// totals, both pass the check, and both insert, driving the ledger negative once both were
// approved. This wraps the whole read-check-insert sequence in one transaction guarded by a
// Postgres advisory transaction lock keyed on the user id (ledger_entries/withdrawal_requests
// have no single per-user row to SELECT ... FOR UPDATE on, since balance is derived by SUM —
// the advisory lock serializes concurrent withdrawal attempts for the same user without needing
// a schema change). Returns an error if the amount exceeds the available balance.
func (r *WalletRepository) CreateWithdrawalRequestIfSufficientBalance(ctx context.Context, userID string, amount float64) (*models.WithdrawalRequest, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, userID); err != nil {
		return nil, fmt.Errorf("acquiring wallet lock: %w", err)
	}

	var balance float64
	if err := tx.QueryRow(ctx, `SELECT COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END), 0)
		FROM ledger_entries WHERE user_id = $1`, userID).Scan(&balance); err != nil {
		return nil, err
	}
	var pending float64
	if err := tx.QueryRow(ctx, `SELECT COALESCE(SUM(amount), 0) FROM withdrawal_requests WHERE user_id = $1 AND status = 'pending'`, userID).Scan(&pending); err != nil {
		return nil, err
	}
	available := balance - pending
	if amount > available {
		return nil, fmt.Errorf("insufficient wallet balance (available: %.2f, %.2f already pending approval)", available, pending)
	}

	wr := &models.WithdrawalRequest{UserID: userID, Amount: amount, Status: "pending"}
	if err := tx.QueryRow(ctx, `
		INSERT INTO withdrawal_requests (user_id, amount) VALUES ($1, $2)
		RETURNING id, status, created_at`,
		userID, amount).Scan(&wr.ID, &wr.Status, &wr.CreatedAt); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
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
	// BUG FIX (M-32): rows.Err() was never checked — a connection drop mid-stream returned
	// (partial rows, nil error), so a truncated wallet history was returned as a silent HTTP
	// 200 with no indication anything was missing.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
