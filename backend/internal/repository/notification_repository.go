package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type NotificationRepository struct {
	db *pgxpool.Pool
}

func NewNotificationRepository(db *pgxpool.Pool) *NotificationRepository {
	return &NotificationRepository{db: db}
}

func (r *NotificationRepository) Create(ctx context.Context, n *models.Notification) error {
	query := `INSERT INTO notifications (user_id, title, body, type, reference_id)
		VALUES ($1,$2,$3,$4,$5) RETURNING id, is_read, created_at`
	return r.db.QueryRow(ctx, query, n.UserID, n.Title, n.Body, n.Type, n.ReferenceID).
		Scan(&n.ID, &n.IsRead, &n.CreatedAt)
}

func (r *NotificationRepository) ListByUser(ctx context.Context, userID string, limit, offset int) ([]models.Notification, error) {
	query := `SELECT id, user_id, title, body, type, reference_id, is_read, created_at
		FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []models.Notification
	for rows.Next() {
		var n models.Notification
		if err := rows.Scan(&n.ID, &n.UserID, &n.Title, &n.Body, &n.Type, &n.ReferenceID, &n.IsRead, &n.CreatedAt); err != nil {
			return nil, err
		}
		list = append(list, n)
	}
	return list, rows.Err()
}

func (r *NotificationRepository) MarkRead(ctx context.Context, id, userID string) error {
	_, err := r.db.Exec(ctx, `UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2`, id, userID)
	return err
}
