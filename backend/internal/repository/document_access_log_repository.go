package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type DocumentAccessLogEntry struct {
	ID         string
	StorageKey string
	UserID     *string
	Action     string // view | download
	IPAddress  *string
	CreatedAt  time.Time
}

// DocumentAccessLogRepository — every view/download of a stored document is recorded here
// (Part 3 "Access Logs / Download Logs", Part 10 "Download Tracking"). Append-only: no
// Update/Delete method exists on this repository by design.
type DocumentAccessLogRepository struct {
	db *pgxpool.Pool
}

func NewDocumentAccessLogRepository(db *pgxpool.Pool) *DocumentAccessLogRepository {
	return &DocumentAccessLogRepository{db: db}
}

func (r *DocumentAccessLogRepository) Record(ctx context.Context, storageKey, userID, action, ip string) error {
	_, err := r.db.Exec(ctx, `INSERT INTO document_access_logs (storage_key, user_id, action, ip_address) VALUES ($1, $2, $3, $4)`,
		storageKey, nullIfEmpty(userID), action, nullIfEmpty(ip))
	return err
}

func (r *DocumentAccessLogRepository) ListForUser(ctx context.Context, userID string, limit int) ([]DocumentAccessLogEntry, error) {
	rows, err := r.db.Query(ctx, `SELECT id, storage_key, user_id, action, ip_address, created_at FROM document_access_logs WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []DocumentAccessLogEntry
	for rows.Next() {
		var e DocumentAccessLogEntry
		if err := rows.Scan(&e.ID, &e.StorageKey, &e.UserID, &e.Action, &e.IPAddress, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
