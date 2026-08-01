package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type AdvertisementRepository struct {
	db *pgxpool.Pool
}

func NewAdvertisementRepository(db *pgxpool.Pool) *AdvertisementRepository {
	return &AdvertisementRepository{db: db}
}

func (r *AdvertisementRepository) Create(ctx context.Context, a *models.Advertisement) error {
	query := `INSERT INTO advertisements (advertiser_id, title, image_url, target_url, ends_at)
		VALUES ($1,$2,$3,$4,$5)
		RETURNING id, is_active, starts_at, created_at`
	return r.db.QueryRow(ctx, query, a.AdvertiserID, a.Title, a.ImageURL, a.TargetURL, a.EndsAt).
		Scan(&a.ID, &a.IsActive, &a.StartsAt, &a.CreatedAt)
}

// ListActive — currently running ads (started, not yet ended, is_active flag on) for the home feed.
func (r *AdvertisementRepository) ListActive(ctx context.Context) ([]models.Advertisement, error) {
	query := `SELECT id, advertiser_id, title, image_url, target_url, is_active, starts_at, ends_at, created_at
		FROM advertisements
		WHERE is_active = true AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now())
		ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Advertisement
	for rows.Next() {
		var a models.Advertisement
		if err := rows.Scan(&a.ID, &a.AdvertiserID, &a.Title, &a.ImageURL, &a.TargetURL, &a.IsActive, &a.StartsAt, &a.EndsAt, &a.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, nil
}

func (r *AdvertisementRepository) ListByAdvertiser(ctx context.Context, advertiserID string) ([]models.Advertisement, error) {
	query := `SELECT id, advertiser_id, title, image_url, target_url, is_active, starts_at, ends_at, created_at
		FROM advertisements WHERE advertiser_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query, advertiserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Advertisement
	for rows.Next() {
		var a models.Advertisement
		if err := rows.Scan(&a.ID, &a.AdvertiserID, &a.Title, &a.ImageURL, &a.TargetURL, &a.IsActive, &a.StartsAt, &a.EndsAt, &a.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, nil
}
