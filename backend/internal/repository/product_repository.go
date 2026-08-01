package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type ProductRepository struct {
	db *pgxpool.Pool
}

func NewProductRepository(db *pgxpool.Pool) *ProductRepository {
	return &ProductRepository{db: db}
}

func (r *ProductRepository) Create(ctx context.Context, p *models.Product) error {
	query := `INSERT INTO products (exporter_id, name, hsn_code, description, unit, unit_price, min_order_qty, image_url)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		RETURNING id, is_active, created_at, updated_at`
	return r.db.QueryRow(ctx, query,
		p.ExporterID, p.Name, p.HSNCode, p.Description, p.Unit, p.UnitPrice, p.MinOrderQty, p.ImageURL,
	).Scan(&p.ID, &p.IsActive, &p.CreatedAt, &p.UpdatedAt)
}

func (r *ProductRepository) GetByID(ctx context.Context, id string) (*models.Product, error) {
	query := `SELECT id, exporter_id, name, hsn_code, description, unit, unit_price, min_order_qty, image_url, is_active, created_at, updated_at
		FROM products WHERE id = $1`
	var p models.Product
	err := r.db.QueryRow(ctx, query, id).Scan(&p.ID, &p.ExporterID, &p.Name, &p.HSNCode, &p.Description, &p.Unit, &p.UnitPrice, &p.MinOrderQty, &p.ImageURL, &p.IsActive, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("product not found")
		}
		return nil, err
	}
	return &p, nil
}

func (r *ProductRepository) ListByExporter(ctx context.Context, exporterID string) ([]models.Product, error) {
	return r.list(ctx, `SELECT id, exporter_id, name, hsn_code, description, unit, unit_price, min_order_qty, image_url, is_active, created_at, updated_at
		FROM products WHERE exporter_id = $1 ORDER BY created_at DESC`, exporterID)
}

// Search — public catalog browse (importers), keyword search over active products only.
func (r *ProductRepository) Search(ctx context.Context, query string, limit int) ([]models.Product, error) {
	return r.list(ctx, `SELECT id, exporter_id, name, hsn_code, description, unit, unit_price, min_order_qty, image_url, is_active, created_at, updated_at
		FROM products
		WHERE is_active = true AND ($2 = '' OR name ILIKE '%' || $2 || '%' OR to_tsvector('english', name) @@ plainto_tsquery('english', $2))
		ORDER BY created_at DESC LIMIT $1`, limit, query)
}

func (r *ProductRepository) list(ctx context.Context, query string, args ...interface{}) ([]models.Product, error) {
	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Product
	for rows.Next() {
		var p models.Product
		if err := rows.Scan(&p.ID, &p.ExporterID, &p.Name, &p.HSNCode, &p.Description, &p.Unit, &p.UnitPrice, &p.MinOrderQty, &p.ImageURL, &p.IsActive, &p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, nil
}

func (r *ProductRepository) Update(ctx context.Context, p *models.Product) error {
	query := `UPDATE products SET name=$1, hsn_code=$2, description=$3, unit=$4, unit_price=$5, min_order_qty=$6, image_url=$7, is_active=$8
		WHERE id = $9 AND exporter_id = $10`
	tag, err := r.db.Exec(ctx, query, p.Name, p.HSNCode, p.Description, p.Unit, p.UnitPrice, p.MinOrderQty, p.ImageURL, p.IsActive, p.ID, p.ExporterID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("product not found or not owned by this exporter")
	}
	return nil
}

// AdminSetActive — admin moderation action, bypasses the exporter-ownership check that Update requires.
func (r *ProductRepository) AdminSetActive(ctx context.Context, id string, active bool) error {
	_, err := r.db.Exec(ctx, `UPDATE products SET is_active = $1 WHERE id = $2`, active, id)
	return err
}

func (r *ProductRepository) Delete(ctx context.Context, id, exporterID string) error {
	tag, err := r.db.Exec(ctx, `DELETE FROM products WHERE id = $1 AND exporter_id = $2`, id, exporterID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("product not found or not owned by this exporter")
	}
	return nil
}
