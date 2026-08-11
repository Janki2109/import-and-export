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
		target_price, destination_country, description, product_image_url, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query,
		rfq.RFQNumber, rfq.ImporterID, rfq.ProductName, rfq.HSNCode, rfq.Quantity, rfq.Unit,
		rfq.TargetPrice, rfq.DestinationCountry, rfq.Description, rfq.ProductImageURL, rfq.Status,
	).Scan(&rfq.ID, &rfq.CreatedAt, &rfq.UpdatedAt)
}

func (r *RFQRepository) GetByID(ctx context.Context, id string) (*models.RFQ, error) {
	query := `SELECT id, rfq_number, importer_id, product_name, hsn_code, quantity, unit,
		target_price, destination_country, description, product_image_url, status, created_at, updated_at
		FROM rfqs WHERE id = $1`
	var rfq models.RFQ
	err := r.db.QueryRow(ctx, query, id).Scan(
		&rfq.ID, &rfq.RFQNumber, &rfq.ImporterID, &rfq.ProductName, &rfq.HSNCode, &rfq.Quantity, &rfq.Unit,
		&rfq.TargetPrice, &rfq.DestinationCountry, &rfq.Description, &rfq.ProductImageURL, &rfq.Status, &rfq.CreatedAt, &rfq.UpdatedAt,
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
		target_price, destination_country, description, product_image_url, status, created_at, updated_at
		FROM rfqs WHERE status = 'open' ORDER BY created_at DESC LIMIT $1 OFFSET $2`, limit, offset)
}

// ListOpenForExporter — Journey 3/4: an open RFQ is visible to an exporter if either (a) it was
// never targeted at anyone specific (rfq_targets has no rows for it — the original open-
// marketplace broadcast behavior, unchanged), or (b) this exporter is one of its targets
// (the importer requested a quotation directly from their profile).
//
// BUG FIX (Journey 4): previously filtered WHERE r.status = 'open' only. MarkRFQQuoted flips an
// RFQ to 'quoted' the moment ANY exporter submits the first quotation, which — combined with
// this filter — made the RFQ vanish from every OTHER exporter's browse list, contradicting
// "multiple exporters can all quote" / "RFQ should not disappear after first quotation".
// 'quoted' just means "has at least one quotation so far", not "closed to further quotes" —
// only 'closed' (set when the importer accepts one) should stop it from being listed.
func (r *RFQRepository) ListOpenForExporter(ctx context.Context, exporterID string, limit, offset int) ([]models.RFQ, error) {
	return r.list(ctx, `
		SELECT r.id, r.rfq_number, r.importer_id, r.product_name, r.hsn_code, r.quantity, r.unit,
			r.target_price, r.destination_country, r.description, r.product_image_url, r.status, r.created_at, r.updated_at
		FROM rfqs r
		WHERE r.status IN ('open', 'quoted')
		AND (
			NOT EXISTS (SELECT 1 FROM rfq_targets rt WHERE rt.rfq_id = r.id)
			OR EXISTS (SELECT 1 FROM rfq_targets rt WHERE rt.rfq_id = r.id AND rt.exporter_id = $3)
		)
		ORDER BY r.created_at DESC LIMIT $1 OFFSET $2`, limit, offset, exporterID)
}

// IsVisibleToExporter — same visibility rule ListOpenForExporter uses: untargeted RFQs are
// visible to every exporter, targeted RFQs only to the exporters they were sent to. Used to
// authorize a single-RFQ lookup (GetByID) the same way the browse listing is already gated.
func (r *RFQRepository) IsVisibleToExporter(ctx context.Context, rfqID, exporterID string) (bool, error) {
	var visible bool
	err := r.db.QueryRow(ctx, `
		SELECT NOT EXISTS (SELECT 1 FROM rfq_targets WHERE rfq_id = $1)
			OR EXISTS (SELECT 1 FROM rfq_targets WHERE rfq_id = $1 AND exporter_id = $2)`,
		rfqID, exporterID).Scan(&visible)
	return visible, err
}

// AddTargets — records which exporters a targeted RFQ was sent to (Journey 3: "request
// quotation" from a specific company profile). Rows here also feed AvgResponseTimeHours.
func (r *RFQRepository) AddTargets(ctx context.Context, rfqID string, exporterIDs []string) error {
	if len(exporterIDs) == 0 {
		return nil
	}
	batch := &pgx.Batch{}
	for _, exporterID := range exporterIDs {
		batch.Queue(`INSERT INTO rfq_targets (rfq_id, exporter_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`, rfqID, exporterID)
	}
	br := r.db.SendBatch(ctx, batch)
	defer br.Close()
	for range exporterIDs {
		if _, err := br.Exec(); err != nil {
			return err
		}
	}
	return nil
}

func (r *RFQRepository) ListByImporter(ctx context.Context, importerID string, limit, offset int) ([]models.RFQ, error) {
	return r.list(ctx, `SELECT id, rfq_number, importer_id, product_name, hsn_code, quantity, unit,
		target_price, destination_country, description, product_image_url, status, created_at, updated_at
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
			&rfq.TargetPrice, &rfq.DestinationCountry, &rfq.Description, &rfq.ProductImageURL, &rfq.Status, &rfq.CreatedAt, &rfq.UpdatedAt,
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
