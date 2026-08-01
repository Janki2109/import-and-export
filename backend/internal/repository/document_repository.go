package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type DocumentRepository struct {
	db *pgxpool.Pool
}

func NewDocumentRepository(db *pgxpool.Pool) *DocumentRepository {
	return &DocumentRepository{db: db}
}

// Upsert — regenerating a document (e.g. after order details changed) replaces the previous file.
func (r *DocumentRepository) Upsert(ctx context.Context, d *models.Document) error {
	query := `INSERT INTO documents (order_id, type, file_url, generated_by)
		VALUES ($1,$2,$3,$4)
		ON CONFLICT (order_id, type) DO UPDATE SET file_url = EXCLUDED.file_url, generated_by = EXCLUDED.generated_by
		RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, d.OrderID, d.Type, d.FileURL, d.GeneratedBy).Scan(&d.ID, &d.CreatedAt)
}

func (r *DocumentRepository) ListByOrder(ctx context.Context, orderID string) ([]models.Document, error) {
	query := `SELECT id, order_id, type, file_url, generated_by, created_at
		FROM documents WHERE order_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Document
	for rows.Next() {
		var d models.Document
		if err := rows.Scan(&d.ID, &d.OrderID, &d.Type, &d.FileURL, &d.GeneratedBy, &d.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, nil
}
