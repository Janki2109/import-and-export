package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type RFQRepository struct {
	db *pgxpool.Pool
}

func NewRFQRepository(db *pgxpool.Pool) *RFQRepository {
	return &RFQRepository{db: db}
}

func (r *RFQRepository) Create(ctx context.Context, rfq *models.RFQ) error {
	query := `INSERT INTO rfqs (rfq_number, importer_id, product_name, hsn_code, quantity, unit,
		target_price, destination_country, description, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query,
		rfq.RFQNumber, rfq.ImporterID, rfq.ProductName, rfq.HSNCode, rfq.Quantity, rfq.Unit,
		rfq.TargetPrice, rfq.DestinationCountry, rfq.Description, rfq.Status,
	).Scan(&rfq.ID, &rfq.CreatedAt, &rfq.UpdatedAt)
}

func (r *RFQRepository) GetByID(ctx context.Context, id string) (*models.RFQ, error) {
	query := `SELECT id, rfq_number, importer_id, product_name, hsn_code, quantity, unit,
		target_price, destination_country, description, status, created_at, updated_at
		FROM rfqs WHERE id = $1`
	var rfq models.RFQ
	err := r.db.QueryRow(ctx, query, id).Scan(
		&rfq.ID, &rfq.RFQNumber, &rfq.ImporterID, &rfq.ProductName, &rfq.HSNCode, &rfq.Quantity, &rfq.Unit,
		&rfq.TargetPrice, &rfq.DestinationCountry, &rfq.Description, &rfq.Status, &rfq.CreatedAt, &rfq.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("rfq not found")
		}
		return nil, err
	}
	return &rfq, nil
}

// ListOpen — browsed by exporters looking for RFQs to quote against.
func (r *RFQRepository) ListOpen(ctx context.Context, limit, offset int) ([]models.RFQ, error) {
	return r.list(ctx, `SELECT id, rfq_number, importer_id, product_name, hsn_code, quantity, unit,
		target_price, destination_country, description, status, created_at, updated_at
		FROM rfqs WHERE status = 'open' ORDER BY created_at DESC LIMIT $1 OFFSET $2`, limit, offset)
}

func (r *RFQRepository) ListByImporter(ctx context.Context, importerID string, limit, offset int) ([]models.RFQ, error) {
	return r.list(ctx, `SELECT id, rfq_number, importer_id, product_name, hsn_code, quantity, unit,
		target_price, destination_country, description, status, created_at, updated_at
		FROM rfqs WHERE importer_id = $3 ORDER BY created_at DESC LIMIT $1 OFFSET $2`, limit, offset, importerID)
}

func (r *RFQRepository) list(ctx context.Context, query string, args ...interface{}) ([]models.RFQ, error) {
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.RFQ
	for rows.Next() {
		var rfq models.RFQ
		if err := rows.Scan(
			&rfq.ID, &rfq.RFQNumber, &rfq.ImporterID, &rfq.ProductName, &rfq.HSNCode, &rfq.Quantity, &rfq.Unit,
			&rfq.TargetPrice, &rfq.DestinationCountry, &rfq.Description, &rfq.Status, &rfq.CreatedAt, &rfq.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, rfq)
	}
	return out, nil
}

func (r *RFQRepository) UpdateStatus(ctx context.Context, id string, status models.RFQStatus) error {
	_, err := r.db.Exec(ctx, `UPDATE rfqs SET status = $1 WHERE id = $2`, status, id)
	return err
}

// RecentBulkCreators — importers who posted more than `threshold` RFQs in the last
// `sinceMinutes` minutes, used by FraudService's "mass RFQ spam" rule (Part 7).
func (r *RFQRepository) RecentBulkCreators(ctx context.Context, sinceMinutes, threshold int) (map[string]int, error) {
	rows, err := r.db.Query(ctx, `
		SELECT importer_id, COUNT(*) FROM rfqs
		WHERE created_at > now() - make_interval(mins => $1)
		GROUP BY importer_id HAVING COUNT(*) > $2`, sinceMinutes, threshold)
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
