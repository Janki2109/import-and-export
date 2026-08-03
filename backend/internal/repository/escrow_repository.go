package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type EscrowRepository struct {
	db *pgxpool.Pool
}

func NewEscrowRepository(db *pgxpool.Pool) *EscrowRepository {
	return &EscrowRepository{db: db}
}

func (r *EscrowRepository) GetByOrderID(ctx context.Context, orderID string) (*models.EscrowPayment, error) {
	query := `SELECT id, order_id, razorpay_order_id, razorpay_payment_id, razorpay_payout_id,
		amount, platform_fee, payout_amount, status, held_at, release_due_at, released_at,
		refunded_at, admin_notified_at, failure_reason, created_at, updated_at
		FROM escrow_payments WHERE order_id = $1`

	var e models.EscrowPayment
	err := r.db.QueryRow(ctx, query, orderID).Scan(
		&e.ID, &e.OrderID, &e.RazorpayOrderID, &e.RazorpayPaymentID, &e.RazorpayPayoutID,
		&e.Amount, &e.PlatformFee, &e.PayoutAmount, &e.Status, &e.HeldAt, &e.ReleaseDueAt,
		&e.ReleasedAt, &e.RefundedAt, &e.AdminNotifiedAt, &e.FailureReason, &e.CreatedAt, &e.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// SetRazorpayOrder stores the razorpay_order_id right after we create the RZP order (before payment capture).
func (r *EscrowRepository) SetRazorpayOrder(ctx context.Context, escrowID, rzpOrderID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE escrow_payments SET razorpay_order_id = $1 WHERE id = $2`,
		rzpOrderID, escrowID)
	return err
}

// MarkHeld is called from the payment-verify handler (after signature check) or the webhook.
// This is the moment money is confirmed collected & sitting in escrow.
func (r *EscrowRepository) MarkHeld(ctx context.Context, orderID, rzpPaymentID string, releaseDueDays int) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// BUG FIX: `($2 || ' days')::interval` concatenates a Go int with a text literal via
	// Postgres's `||` operator, which requires both operands to already be text — pgx has no
	// encode plan for binding a bare int parameter as text, so this failed on every single
	// call (see docs/BUGFIXES.md). make_interval() takes the int directly, correctly typed.
	cmd, err := tx.Exec(ctx, `
		UPDATE escrow_payments
		SET status = 'held',
		    razorpay_payment_id = $1,
		    held_at = now(),
		    release_due_at = now() + make_interval(days => $2)
		WHERE order_id = $3 AND status IN ('created','authorized')`,
		rzpPaymentID, releaseDueDays, orderID)
	if err != nil {
		return fmt.Errorf("update escrow to held: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("escrow payment for order %s is not in a holdable state", orderID)
	}

	_, err = tx.Exec(ctx, `UPDATE orders SET status = 'payment_held' WHERE id = $1`, orderID)
	if err != nil {
		return fmt.Errorf("update order status: %w", err)
	}

	// Ledger: platform received money (credit to platform, held liability)
	_, err = tx.Exec(ctx, `
		INSERT INTO ledger_entries (order_id, user_id, entry_type, amount, description, reference_id)
		VALUES ($1, NULL, 'credit', (SELECT amount FROM escrow_payments WHERE order_id = $1), 'Payment collected & held in escrow', $2)`,
		orderID, rzpPaymentID)
	if err != nil {
		return fmt.Errorf("ledger entry: %w", err)
	}

	return tx.Commit(ctx)
}

// MarkReleased — called after delivery confirmed (by importer, admin, or the auto-release
// cron). exporterID needed for ledger entry. Accepts escrow in either 'held' or 'on_hold'
// (admin can release a payment they'd previously put on hold).
func (r *EscrowRepository) MarkReleased(ctx context.Context, orderID, exporterID, rzpPayoutID string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var payoutAmount, platformFee float64
	err = tx.QueryRow(ctx, `
		UPDATE escrow_payments
		SET status = 'released', razorpay_payout_id = $1, released_at = now()
		WHERE order_id = $2 AND status IN ('held', 'on_hold')
		RETURNING payout_amount, platform_fee`,
		rzpPayoutID, orderID).Scan(&payoutAmount, &platformFee)
	if err != nil {
		return fmt.Errorf("update escrow to released: %w", err)
	}

	_, err = tx.Exec(ctx, `UPDATE orders SET status = 'payment_released' WHERE id = $1`, orderID)
	if err != nil {
		return err
	}

	// Ledger: debit platform's held liability, credit exporter payout, credit platform fee revenue
	_, err = tx.Exec(ctx, `
		INSERT INTO ledger_entries (order_id, user_id, entry_type, amount, description, reference_id)
		VALUES
			($1, $2, 'credit', $3, 'Payout released for delivered order', $4),
			($1, NULL, 'credit', $5, 'Platform fee earned', $4)`,
		orderID, exporterID, payoutAmount, rzpPayoutID, platformFee)
	if err != nil {
		return fmt.Errorf("ledger entries: %w", err)
	}

	return tx.Commit(ctx)
}

// MarkRefunded — used when order is cancelled before delivery / dispute resolved in importer's
// favor / admin directly refunds. Accepts escrow in either 'held' or 'on_hold'.
//
// BUG FIX: this previously (a) never checked whether the escrow UPDATE actually matched a
// row — an already-released or already-refunded escrow would silently no-op that statement
// while the *unconditional* second UPDATE still flipped orders.status to 'refunded' anyway,
// desynchronizing order/escrow state with no error; and (b) never wrote any ledger entries,
// so a "successful" refund moved no money at all — the platform's held liability was never
// reversed and the importer was never credited back. Both are fixed below: the escrow update
// result is checked before proceeding, and the same debit/credit ledger pair MarkHeld/
// MarkReleased already use for their transitions is mirrored here for the reversal.
func (r *EscrowRepository) MarkRefunded(ctx context.Context, orderID, importerID string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var amount float64
	err = tx.QueryRow(ctx, `
		UPDATE escrow_payments SET status = 'refunded', refunded_at = now()
		WHERE order_id = $1 AND status IN ('held', 'on_hold')
		RETURNING amount`, orderID).Scan(&amount)
	if err != nil {
		return fmt.Errorf("escrow payment for order %s is not in a refundable state: %w", orderID, err)
	}

	if _, err := tx.Exec(ctx, `UPDATE orders SET status = 'refunded' WHERE id = $1`, orderID); err != nil {
		return err
	}

	// Ledger: reverse the platform's held liability, credit the importer back in full.
	_, err = tx.Exec(ctx, `
		INSERT INTO ledger_entries (order_id, user_id, entry_type, amount, description, reference_id)
		VALUES
			($1, NULL, 'debit', $2, 'Escrow refunded — held liability reversed', $3),
			($1, $4, 'credit', $2, 'Refund credited', $3)`,
		orderID, amount, orderID, importerID)
	if err != nil {
		return fmt.Errorf("ledger entries: %w", err)
	}

	return tx.Commit(ctx)
}

// MarkOnHold — admin pauses a held payment (e.g. pending investigation), which also blocks
// the auto-release cron from releasing it on schedule until admin releases or refunds it.
func (r *EscrowRepository) MarkOnHold(ctx context.Context, orderID string) error {
	_, err := r.db.Exec(ctx, `UPDATE escrow_payments SET status = 'on_hold' WHERE order_id = $1 AND status = 'held'`, orderID)
	return err
}

// MarkAdminNotified — the auto-release timer calls this once it's sent the "escrow due for
// release" notification to admin, so the cron doesn't re-notify every pass.
func (r *EscrowRepository) MarkAdminNotified(ctx context.Context, orderID string) error {
	_, err := r.db.Exec(ctx, `UPDATE escrow_payments SET admin_notified_at = now() WHERE order_id = $1`, orderID)
	return err
}

// EscrowSummary — aggregate totals for the admin escrow dashboard.
type EscrowSummary struct {
	HoldingBalance   float64 `json:"holding_balance"`   // held + on_hold, not yet released or refunded
	PendingRelease   float64 `json:"pending_release"`    // held only (on_hold excluded — it's paused, not "pending")
	TotalReleased    float64 `json:"total_released"`
	TotalRefunded    float64 `json:"total_refunded"`
}

func (r *EscrowRepository) GetSummary(ctx context.Context) (*EscrowSummary, error) {
	s := &EscrowSummary{}
	err := r.db.QueryRow(ctx, `SELECT
		COALESCE(SUM(amount) FILTER (WHERE status IN ('held','on_hold')), 0),
		COALESCE(SUM(amount) FILTER (WHERE status = 'held'), 0),
		COALESCE(SUM(payout_amount) FILTER (WHERE status = 'released'), 0),
		COALESCE(SUM(amount) FILTER (WHERE status = 'refunded'), 0)
		FROM escrow_payments`).Scan(&s.HoldingBalance, &s.PendingRelease, &s.TotalReleased, &s.TotalRefunded)
	if err != nil {
		return nil, err
	}
	return s, nil
}

// EscrowOrderRow — one row for the admin "Escrow Payments" list: order + escrow + the two
// parties' names joined in, so the screen doesn't need N extra profile lookups.
type EscrowOrderRow struct {
	OrderID          string     `json:"order_id"`
	OrderNumber      string     `json:"order_number"`
	ImporterID       string     `json:"importer_id"`
	ImporterName     string     `json:"importer_name"`
	ExporterID       string     `json:"exporter_id"`
	ExporterName     string     `json:"exporter_name"`
	OrderAmount      float64    `json:"order_amount"`
	PayoutAmount     float64    `json:"payout_amount"`
	OrderStatus      string     `json:"order_status"`
	EscrowStatus     string     `json:"escrow_status"`
	HasOpenDispute   bool       `json:"has_open_dispute"`
	ReleaseDueAt     *time.Time `json:"release_due_at,omitempty"`
	HeldAt           *time.Time `json:"held_at,omitempty"`
	ReleasedAt       *time.Time `json:"released_at,omitempty"`
	RefundedAt       *time.Time `json:"refunded_at,omitempty"`
}

// ExporterEscrowTotals — the exporter's own escrow-side figures for their Wallet screen:
// how much is still held (pending release) vs already released to them historically.
type ExporterEscrowTotals struct {
	PendingRelease float64 `json:"pending_release"`
	TotalReleased  float64 `json:"total_released"`
}

func (r *EscrowRepository) GetExporterTotals(ctx context.Context, exporterID string) (*ExporterEscrowTotals, error) {
	t := &ExporterEscrowTotals{}
	err := r.db.QueryRow(ctx, `SELECT
		COALESCE(SUM(e.amount) FILTER (WHERE e.status IN ('held','on_hold')), 0),
		COALESCE(SUM(e.payout_amount) FILTER (WHERE e.status = 'released'), 0)
		FROM escrow_payments e JOIN orders o ON o.id = e.order_id
		WHERE o.exporter_id = $1`, exporterID).Scan(&t.PendingRelease, &t.TotalReleased)
	if err != nil {
		return nil, err
	}
	return t, nil
}

// ListEscrowOrders — every order that has an escrow row (i.e. payment was at least
// self-declared), newest first, optionally filtered by escrow status.
func (r *EscrowRepository) ListEscrowOrders(ctx context.Context, escrowStatus *string, limit, offset int) ([]EscrowOrderRow, error) {
	query := `SELECT
		o.id, o.order_number, o.importer_id, imp.full_name, o.exporter_id, exp.full_name,
		o.total_amount, e.payout_amount, o.status, e.status,
		EXISTS(SELECT 1 FROM disputes d WHERE d.order_id = o.id AND d.status = 'open'),
		e.release_due_at, e.held_at, e.released_at, e.refunded_at
		FROM escrow_payments e
		JOIN orders o ON o.id = e.order_id
		JOIN users imp ON imp.id = o.importer_id
		JOIN users exp ON exp.id = o.exporter_id
		WHERE ($1::text IS NULL OR e.status::text = $1)
		ORDER BY o.created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, escrowStatus, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []EscrowOrderRow
	for rows.Next() {
		var row EscrowOrderRow
		if err := rows.Scan(&row.OrderID, &row.OrderNumber, &row.ImporterID, &row.ImporterName,
			&row.ExporterID, &row.ExporterName, &row.OrderAmount, &row.PayoutAmount,
			&row.OrderStatus, &row.EscrowStatus, &row.HasOpenDispute,
			&row.ReleaseDueAt, &row.HeldAt, &row.ReleasedAt, &row.RefundedAt); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}
