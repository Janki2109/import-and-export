package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type QuotationRepository struct {
	db *pgxpool.Pool
}

func NewQuotationRepository(db *pgxpool.Pool) *QuotationRepository {
	return &QuotationRepository{db: db}
}

func (r *QuotationRepository) Create(ctx context.Context, q *models.Quotation) error {
	query := `INSERT INTO quotations (rfq_id, exporter_id, unit_price, quantity, total_amount,
		validity_date, terms, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query,
		q.RFQID, q.ExporterID, q.UnitPrice, q.Quantity, q.TotalAmount, q.ValidityDate, q.Terms, q.Status,
	).Scan(&q.ID, &q.CreatedAt, &q.UpdatedAt)
}

func (r *QuotationRepository) GetByID(ctx context.Context, id string) (*models.Quotation, error) {
	query := `SELECT id, rfq_id, exporter_id, unit_price, quantity, total_amount, validity_date,
		terms, status, order_id, created_at, updated_at FROM quotations WHERE id = $1`
	var q models.Quotation
	err := r.db.QueryRow(ctx, query, id).Scan(
		&q.ID, &q.RFQID, &q.ExporterID, &q.UnitPrice, &q.Quantity, &q.TotalAmount, &q.ValidityDate,
		&q.Terms, &q.Status, &q.OrderID, &q.CreatedAt, &q.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("quotation not found")
		}
		return nil, err
	}
	return &q, nil
}

func (r *QuotationRepository) ListByRFQ(ctx context.Context, rfqID string) ([]models.Quotation, error) {
	query := `SELECT id, rfq_id, exporter_id, unit_price, quantity, total_amount, validity_date,
		terms, status, order_id, created_at, updated_at FROM quotations WHERE rfq_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query, rfqID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Quotation
	for rows.Next() {
		var q models.Quotation
		if err := rows.Scan(
			&q.ID, &q.RFQID, &q.ExporterID, &q.UnitPrice, &q.Quantity, &q.TotalAmount, &q.ValidityDate,
			&q.Terms, &q.Status, &q.OrderID, &q.CreatedAt, &q.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, q)
	}
	return out, nil
}

func (r *QuotationRepository) ListByExporter(ctx context.Context, exporterID string) ([]models.Quotation, error) {
	query := `SELECT id, rfq_id, exporter_id, unit_price, quantity, total_amount, validity_date,
		terms, status, order_id, created_at, updated_at FROM quotations WHERE exporter_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query, exporterID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Quotation
	for rows.Next() {
		var q models.Quotation
		if err := rows.Scan(
			&q.ID, &q.RFQID, &q.ExporterID, &q.UnitPrice, &q.Quantity, &q.TotalAmount, &q.ValidityDate,
			&q.Terms, &q.Status, &q.OrderID, &q.CreatedAt, &q.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, q)
	}
	return out, nil
}

// Accept marks this quotation accepted + links it to the newly created order,
// rejects every other quotation on the same RFQ, and closes the RFQ — all atomically.
func (r *QuotationRepository) Accept(ctx context.Context, quotationID, rfqID, orderID string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// RACE FIX (C-08): previously this UPDATE had no `AND status = 'pending'` guard and no
	// RowsAffected check — the Go-level status check in the service ran before either of two
	// concurrent Accept calls (double-tap / client retry) committed its write, so both could
	// pass and both call CreateOrder, leaving the importer with two orders/two escrow rows for
	// one quotation (the second Accept's order_id UPDATE here would also silently orphan the
	// first order). The UPDATE is now itself the atomic gate.
	cmd, err := tx.Exec(ctx,
		`UPDATE quotations SET status = 'accepted', order_id = $1 WHERE id = $2 AND status = 'pending'`,
		orderID, quotationID)
	if err != nil {
		return fmt.Errorf("accept quotation: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("quotation is not in a pending state (already accepted/rejected)")
	}

	if _, err := tx.Exec(ctx,
		`UPDATE quotations SET status = 'rejected' WHERE rfq_id = $1 AND id != $2 AND status = 'pending'`,
		rfqID, quotationID); err != nil {
		return fmt.Errorf("reject other quotations: %w", err)
	}

	if _, err := tx.Exec(ctx, `UPDATE rfqs SET status = 'closed' WHERE id = $1`, rfqID); err != nil {
		return fmt.Errorf("close rfq: %w", err)
	}

	return tx.Commit(ctx)
}

func (r *QuotationRepository) MarkRFQQuoted(ctx context.Context, rfqID string) error {
	_, err := r.db.Exec(ctx, `UPDATE rfqs SET status = 'quoted' WHERE id = $1 AND status = 'open'`, rfqID)
	return err
}

// RecentBulkCreators — exporters who submitted more than `threshold` quotations in the last
// `sinceMinutes` minutes, used by FraudService's "mass quotation spam" rule (Part 7).
func (r *QuotationRepository) RecentBulkCreators(ctx context.Context, sinceMinutes, threshold int) (map[string]int, error) {
	rows, err := r.db.Query(ctx, `
		SELECT exporter_id, COUNT(*) FROM quotations
		WHERE created_at > now() - make_interval(mins => $1)
		GROUP BY exporter_id HAVING COUNT(*) > $2`, sinceMinutes, threshold)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[string]int)
	for rows.Next() {
		var userID string
		var count int
		if err := rows.Scan(&userID, &count); err != nil {
			return nil, err
		}
		out[userID] = count
	}
	return out, rows.Err()
}
