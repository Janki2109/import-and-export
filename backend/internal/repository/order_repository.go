package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type OrderRepository struct {
	db *pgxpool.Pool
}

func NewOrderRepository(db *pgxpool.Pool) *OrderRepository {
	return &OrderRepository{db: db}
}

// CreateOrderWithEscrow creates the order + escrow_payment row in a single DB transaction.
// This is critical: order aur payment record hamesha atomically banne chahiye,
// warna ek bina payment-tracking ke order ban sakta hai (data inconsistency).
func (r *OrderRepository) CreateOrderWithEscrow(ctx context.Context, order *models.Order, escrow *models.EscrowPayment) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) // no-op if committed

	orderQuery := `
		INSERT INTO orders (
			order_number, importer_id, exporter_id, product_name, hsn_code,
			quantity, unit, unit_price, currency, total_amount,
			platform_fee_percent, platform_fee_amount, exporter_payout_amount,
			status, auto_release_days, delivery_address, notes
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
		RETURNING id, created_at, updated_at`

	err = tx.QueryRow(ctx, orderQuery,
		order.OrderNumber, order.ImporterID, order.ExporterID, order.ProductName, order.HSNCode,
		order.Quantity, order.Unit, order.UnitPrice, order.Currency, order.TotalAmount,
		order.PlatformFeePercent, order.PlatformFeeAmount, order.ExporterPayoutAmount,
		order.Status, order.AutoReleaseDays, order.DeliveryAddress, order.Notes,
	).Scan(&order.ID, &order.CreatedAt, &order.UpdatedAt)
	if err != nil {
		return fmt.Errorf("insert order: %w", err)
	}

	escrow.OrderID = order.ID
	escrowQuery := `
		INSERT INTO escrow_payments (order_id, amount, platform_fee, payout_amount, status)
		VALUES ($1,$2,$3,$4,$5)
		RETURNING id, created_at, updated_at`

	err = tx.QueryRow(ctx, escrowQuery,
		escrow.OrderID, escrow.Amount, escrow.PlatformFee, escrow.PayoutAmount, escrow.Status,
	).Scan(&escrow.ID, &escrow.CreatedAt, &escrow.UpdatedAt)
	if err != nil {
		return fmt.Errorf("insert escrow: %w", err)
	}

	// Also create the shipment placeholder row (pending, unassigned)
	shipmentQuery := `
		INSERT INTO shipments (order_id, status, pickup_address, delivery_address)
		VALUES ($1, 'pending', NULL, $2)`
	if _, err := tx.Exec(ctx, shipmentQuery, order.ID, order.DeliveryAddress); err != nil {
		return fmt.Errorf("insert shipment placeholder: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *OrderRepository) GetByID(ctx context.Context, id string) (*models.Order, error) {
	query := `SELECT id, order_number, importer_id, exporter_id, product_name, hsn_code,
		quantity, unit, unit_price, currency, total_amount, platform_fee_percent,
		platform_fee_amount, exporter_payout_amount, status, auto_release_days,
		delivery_address, notes, created_at, updated_at
		FROM orders WHERE id = $1`

	var o models.Order
	err := r.db.QueryRow(ctx, query, id).Scan(
		&o.ID, &o.OrderNumber, &o.ImporterID, &o.ExporterID, &o.ProductName, &o.HSNCode,
		&o.Quantity, &o.Unit, &o.UnitPrice, &o.Currency, &o.TotalAmount, &o.PlatformFeePercent,
		&o.PlatformFeeAmount, &o.ExporterPayoutAmount, &o.Status, &o.AutoReleaseDays,
		&o.DeliveryAddress, &o.Notes, &o.CreatedAt, &o.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("order not found")
		}
		return nil, err
	}
	return &o, nil
}

func (r *OrderRepository) ListByUser(ctx context.Context, userID string, role models.UserRole, status *string, limit, offset int) ([]models.Order, error) {
	// BUG FIX (L-12): previously silently fell back to importer_id for ANY role that wasn't
	// exactly "exporter" — logistics and admin callers (GET /orders has no RequireRole) got a
	// silent empty 200 that reads as "you have no orders" rather than "this role isn't
	// supported by this endpoint", with no error to signal the real cause.
	col := "importer_id"
	switch role {
	case models.RoleExporter:
		col = "exporter_id"
	case models.RoleImporter:
		col = "importer_id"
	default:
		return nil, fmt.Errorf("orders list is not available for role %q", role)
	}

	query := fmt.Sprintf(`SELECT id, order_number, importer_id, exporter_id, product_name, hsn_code,
		quantity, unit, unit_price, currency, total_amount, platform_fee_percent,
		platform_fee_amount, exporter_payout_amount, status, auto_release_days,
		delivery_address, notes, created_at, updated_at
		FROM orders WHERE %s = $1 AND ($2::text IS NULL OR status::text = $2)
		ORDER BY created_at DESC LIMIT $3 OFFSET $4`, col)

	rows, err := r.db.Query(ctx, query, userID, status, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orders []models.Order
	for rows.Next() {
		var o models.Order
		if err := rows.Scan(
			&o.ID, &o.OrderNumber, &o.ImporterID, &o.ExporterID, &o.ProductName, &o.HSNCode,
			&o.Quantity, &o.Unit, &o.UnitPrice, &o.Currency, &o.TotalAmount, &o.PlatformFeePercent,
			&o.PlatformFeeAmount, &o.ExporterPayoutAmount, &o.Status, &o.AutoReleaseDays,
			&o.DeliveryAddress, &o.Notes, &o.CreatedAt, &o.UpdatedAt,
		); err != nil {
			return nil, err
		}
		orders = append(orders, o)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return orders, rows.Err()
}

// HasOrderBetween — Journey 8: whether these two users share at least one order together
// (either as importer/exporter). Used to gate chat to actual trade partners instead of any
// importer being able to message any exporter platform-wide with no relationship.
func (r *OrderRepository) HasOrderBetween(ctx context.Context, userA, userB string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM orders
			WHERE (importer_id = $1 AND exporter_id = $2) OR (importer_id = $2 AND exporter_id = $1)
		)`, userA, userB).Scan(&exists)
	return exists, err
}

func (r *OrderRepository) UpdateStatus(ctx context.Context, orderID string, status models.OrderStatus) error {
	_, err := r.db.Exec(ctx, `UPDATE orders SET status = $1 WHERE id = $2`, status, orderID)
	return err
}

// GetOrdersDueForAutoRelease finds held payments past their release_due_at — used by the cron job.
func (r *OrderRepository) GetOrdersDueForAutoRelease(ctx context.Context) ([]models.EscrowPayment, error) {
	query := `SELECT id, order_id, razorpay_order_id, razorpay_payment_id, razorpay_payout_id,
		amount, platform_fee, payout_amount, status, held_at, release_due_at, released_at,
		refunded_at, admin_notified_at, failure_reason, created_at, updated_at
		FROM escrow_payments
		WHERE status = 'held' AND release_due_at <= now()`

	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var payments []models.EscrowPayment
	for rows.Next() {
		var e models.EscrowPayment
		if err := rows.Scan(
			&e.ID, &e.OrderID, &e.RazorpayOrderID, &e.RazorpayPaymentID, &e.RazorpayPayoutID,
			&e.Amount, &e.PlatformFee, &e.PayoutAmount, &e.Status, &e.HeldAt, &e.ReleaseDueAt,
			&e.ReleasedAt, &e.RefundedAt, &e.AdminNotifiedAt, &e.FailureReason, &e.CreatedAt, &e.UpdatedAt,
		); err != nil {
			return nil, err
		}
		payments = append(payments, e)
	}
	// BUG FIX (M-31): rows.Err() was never checked — a connection drop mid-stream returned
	// (partial rows, nil error), so the auto-release cron treated a truncated pass as fully
	// successful and the remaining due escrows silently never got processed that tick.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return payments, rows.Err()
}
