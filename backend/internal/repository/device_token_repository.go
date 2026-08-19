package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

type DeviceTokenRepository struct {
	db *pgxpool.Pool
}

func NewDeviceTokenRepository(db *pgxpool.Pool) *DeviceTokenRepository {
	return &DeviceTokenRepository{db: db}
}

// Register — upsert on token so re-registering the same device (e.g. after reinstall) is a no-op update.
func (r *DeviceTokenRepository) Register(ctx context.Context, userID, token, platform string) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO device_tokens (user_id, token, platform)
		VALUES ($1, $2, $3)
		ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform`,
		userID, token, platform)
	return err
}

func (r *DeviceTokenRepository) ListTokensForUser(ctx context.Context, userID string) ([]string, error) {
	rows, err := r.db.Query(ctx, `SELECT token FROM device_tokens WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		tokens = append(tokens, t)
	}
	return tokens, rows.Err()
}

func (r *DeviceTokenRepository) Unregister(ctx context.Context, token string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM device_tokens WHERE token = $1`, token)
	return err
}
