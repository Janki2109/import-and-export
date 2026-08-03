package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type DisputeRepository struct {
	db *pgxpool.Pool
}

func NewDisputeRepository(db *pgxpool.Pool) *DisputeRepository {
	return &DisputeRepository{db: db}
}

func (r *DisputeRepository) Create(ctx context.Context, d *models.Dispute) error {
	query := `INSERT INTO disputes (order_id, raised_by, reason, status)
		VALUES ($1, $2, $3, 'open')
		RETURNING id, status, created_at`
	return r.db.QueryRow(ctx, query, d.OrderID, d.RaisedBy, d.Reason).Scan(&d.ID, &d.Status, &d.CreatedAt)
}

func (r *DisputeRepository) GetByID(ctx context.Context, id string) (*models.Dispute, error) {
	query := `SELECT id, order_id, raised_by, reason, status, resolution_notes, resolved_by, resolved_at, created_at
		FROM disputes WHERE id = $1`
	var d models.Dispute
	err := r.db.QueryRow(ctx, query, id).Scan(
		&d.ID, &d.OrderID, &d.RaisedBy, &d.Reason, &d.Status, &d.ResolutionNotes, &d.ResolvedBy, &d.ResolvedAt, &d.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("dispute not found")
		}
		return nil, err
	}
	return &d, nil
}

func (r *DisputeRepository) GetOpenByOrderID(ctx context.Context, orderID string) (*models.Dispute, error) {
	query := `SELECT id, order_id, raised_by, reason, status, resolution_notes, resolved_by, resolved_at, created_at
		FROM disputes WHERE order_id = $1 AND status = 'open' LIMIT 1`
	var d models.Dispute
	err := r.db.QueryRow(ctx, query, orderID).Scan(
		&d.ID, &d.OrderID, &d.RaisedBy, &d.Reason, &d.Status, &d.ResolutionNotes, &d.ResolvedBy, &d.ResolvedAt, &d.CreatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}

func (r *DisputeRepository) ListOpen(ctx context.Context) ([]models.Dispute, error) {
	return r.list(ctx, `SELECT id, order_id, raised_by, reason, status, resolution_notes, resolved_by, resolved_at, created_at
		FROM disputes WHERE status = 'open' ORDER BY created_at ASC`)
}

func (r *DisputeRepository) ListByUser(ctx context.Context, userID string) ([]models.Dispute, error) {
	return r.list(ctx, `SELECT id, order_id, raised_by, reason, status, resolution_notes, resolved_by, resolved_at, created_at
		FROM disputes WHERE raised_by = $1 ORDER BY created_at DESC`, userID)
}

func (r *DisputeRepository) list(ctx context.Context, query string, args ...interface{}) ([]models.Dispute, error) {
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Dispute
	for rows.Next() {
		var d models.Dispute
		if err := rows.Scan(&d.ID, &d.OrderID, &d.RaisedBy, &d.Reason, &d.Status, &d.ResolutionNotes, &d.ResolvedBy, &d.ResolvedAt, &d.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, nil
}

// BUG FIX (Journey 7): previously updated by id alone with no status guard — the service-layer
// "already resolved?" check (dispute_service.go) is read-then-write, so two concurrent resolve
// requests could both pass that check before either write landed, both proceeding to move money
// via their own resolution branch. Constraining the WHERE clause to status='open' closes that
// TOCTOU window: only the first concurrent request can actually flip the row.
func (r *DisputeRepository) Resolve(ctx context.Context, id, resolvedBy, status, notes string) error {
	cmd, err := r.db.Exec(ctx, `
		UPDATE disputes SET status = $1, resolution_notes = $2, resolved_by = $3, resolved_at = now()
		WHERE id = $4 AND status = 'open'`, status, notes, resolvedBy, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("dispute is already resolved")
	}
	return nil
}
