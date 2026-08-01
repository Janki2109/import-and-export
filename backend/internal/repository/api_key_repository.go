package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type APIKeyRepository struct {
	db *pgxpool.Pool
}

func NewAPIKeyRepository(db *pgxpool.Pool) *APIKeyRepository {
	return &APIKeyRepository{db: db}
}

func (r *APIKeyRepository) Create(ctx context.Context, userID, keyHash string, label *string) (*models.APIKey, error) {
	k := &models.APIKey{UserID: userID, Label: label}
	query := `INSERT INTO api_keys (user_id, key_hash, label) VALUES ($1,$2,$3) RETURNING id, created_at`
	if err := r.db.QueryRow(ctx, query, userID, keyHash, label).Scan(&k.ID, &k.CreatedAt); err != nil {
		return nil, err
	}
	return k, nil
}

func (r *APIKeyRepository) ListByUser(ctx context.Context, userID string) ([]models.APIKey, error) {
	query := `SELECT id, user_id, label, last_used_at, revoked, created_at FROM api_keys WHERE user_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.APIKey
	for rows.Next() {
		var k models.APIKey
		if err := rows.Scan(&k.ID, &k.UserID, &k.Label, &k.LastUsedAt, &k.Revoked, &k.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, k)
	}
	return out, nil
}

func (r *APIKeyRepository) Revoke(ctx context.Context, id, userID string) error {
	_, err := r.db.Exec(ctx, `UPDATE api_keys SET revoked = true WHERE id = $1 AND user_id = $2`, id, userID)
	return err
}

// UserIDForValidKey — resolves a non-revoked key hash to (userID, role), updating last_used_at.
// Returns ("", "", nil) if the key isn't found/valid.
func (r *APIKeyRepository) UserIDForValidKey(ctx context.Context, keyHash string) (userID, role string, err error) {
	query := `UPDATE api_keys SET last_used_at = now()
		WHERE key_hash = $1 AND revoked = false
		RETURNING user_id`
	err = r.db.QueryRow(ctx, query, keyHash).Scan(&userID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", "", nil
		}
		return "", "", err
	}

	err = r.db.QueryRow(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if err != nil {
		return "", "", err
	}
	return userID, role, nil
}
