package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type DocumentRepository struct {
	db *pgxpool.Pool
}

func NewDocumentRepository(db *pgxpool.Pool) *DocumentRepository {
	return &DocumentRepository{db: db}
}

// GetByOrderAndType — used by Generate to find the existing "current version" row (if any)
// before deciding the next version number.
func (r *DocumentRepository) GetByOrderAndType(ctx context.Context, orderID string, docType models.DocumentType) (*models.Document, error) {
	query := `SELECT id, order_id, type, storage_key, version, checksum, signature, generated_by, created_at, updated_at
		FROM documents WHERE order_id = $1 AND type = $2`
	var d models.Document
	err := r.db.QueryRow(ctx, query, orderID, docType).Scan(
		&d.ID, &d.OrderID, &d.Type, &d.StorageKey, &d.Version, &d.Checksum, &d.Signature, &d.GeneratedBy, &d.CreatedAt, &d.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}

// Upsert — writes the new current version. Journey 9 "version history": unlike the old
// behavior (silently overwriting file_url in place), the caller is responsible for having
// already inserted the corresponding row into document_versions via AddVersion — this only
// ever moves the "current" pointer forward, it never destroys prior version rows.
func (r *DocumentRepository) Upsert(ctx context.Context, d *models.Document) error {
	query := `INSERT INTO documents (order_id, type, storage_key, version, checksum, signature, generated_by)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT (order_id, type) DO UPDATE SET
			storage_key = EXCLUDED.storage_key, version = EXCLUDED.version,
			checksum = EXCLUDED.checksum, signature = EXCLUDED.signature,
			generated_by = EXCLUDED.generated_by, updated_at = now()
		RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query, d.OrderID, d.Type, d.StorageKey, d.Version, d.Checksum, d.Signature, d.GeneratedBy).
		Scan(&d.ID, &d.CreatedAt, &d.UpdatedAt)
}

// AddVersion — appends an immutable version-history row. Called once per Generate, before
// Upsert moves the "current" pointer.
func (r *DocumentRepository) AddVersion(ctx context.Context, v *models.DocumentVersion) error {
	query := `INSERT INTO document_versions (document_id, version, storage_key, checksum, signature, generated_by)
		VALUES ($1,$2,$3,$4,$5,$6)
		RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, v.DocumentID, v.Version, v.StorageKey, v.Checksum, v.Signature, v.GeneratedBy).
		Scan(&v.ID, &v.CreatedAt)
}

func (r *DocumentRepository) ListVersions(ctx context.Context, documentID string) ([]models.DocumentVersion, error) {
	query := `SELECT id, document_id, version, storage_key, checksum, signature, generated_by, created_at
		FROM document_versions WHERE document_id = $1 ORDER BY version DESC`
	rows, err := r.db.Query(ctx, query, documentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.DocumentVersion
	for rows.Next() {
		var v models.DocumentVersion
		if err := rows.Scan(&v.ID, &v.DocumentID, &v.Version, &v.StorageKey, &v.Checksum, &v.Signature, &v.GeneratedBy, &v.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (r *DocumentRepository) GetByID(ctx context.Context, id string) (*models.Document, error) {
	query := `SELECT id, order_id, type, storage_key, version, checksum, signature, generated_by, created_at, updated_at
		FROM documents WHERE id = $1`
	var d models.Document
	err := r.db.QueryRow(ctx, query, id).Scan(
		&d.ID, &d.OrderID, &d.Type, &d.StorageKey, &d.Version, &d.Checksum, &d.Signature, &d.GeneratedBy, &d.CreatedAt, &d.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}

func (r *DocumentRepository) ListByOrder(ctx context.Context, orderID string) ([]models.Document, error) {
	query := `SELECT id, order_id, type, storage_key, version, checksum, signature, generated_by, created_at, updated_at
		FROM documents WHERE order_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Document
	for rows.Next() {
		var d models.Document
		if err := rows.Scan(&d.ID, &d.OrderID, &d.Type, &d.StorageKey, &d.Version, &d.Checksum, &d.Signature, &d.GeneratedBy, &d.CreatedAt, &d.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// Delete — Journey 9 "no orphan files": the caller (DocumentService) is responsible for also
// deleting every version's storage_key from StorageService before/after calling this, since
// the DB rows alone don't reach into storage.
func (r *DocumentRepository) Delete(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM documents WHERE id = $1`, id)
	return err
}
