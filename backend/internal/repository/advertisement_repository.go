package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type AdvertisementRepository struct {
	db *pgxpool.Pool
}

func NewAdvertisementRepository(db *pgxpool.Pool) *AdvertisementRepository {
	return &AdvertisementRepository{db: db}
}

const adColumns = `a.id, a.advertiser_id, u.full_name, u.role, a.title, a.description, a.category, a.media_type,
	a.image_url, a.price, a.contact_info, a.views, a.target_url, a.is_active, a.starts_at, a.ends_at, a.created_at`

func scanAd(row pgx.Row) (models.Advertisement, error) {
	var a models.Advertisement
	err := row.Scan(&a.ID, &a.AdvertiserID, &a.AdvertiserName, &a.AdvertiserRole, &a.Title, &a.Description, &a.Category,
		&a.MediaType, &a.ImageURL, &a.Price, &a.ContactInfo, &a.Views, &a.TargetURL, &a.IsActive, &a.StartsAt, &a.EndsAt, &a.CreatedAt)
	return a, err
}

func (r *AdvertisementRepository) Create(ctx context.Context, a *models.Advertisement) error {
	query := `INSERT INTO advertisements (advertiser_id, title, description, category, media_type, image_url, price, contact_info, target_url, ends_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING id, is_active, starts_at, created_at`
	return r.db.QueryRow(ctx, query, a.AdvertiserID, a.Title, a.Description, a.Category, a.MediaType, a.ImageURL, a.Price, a.ContactInfo, a.TargetURL, a.EndsAt).
		Scan(&a.ID, &a.IsActive, &a.StartsAt, &a.CreatedAt)
}

// ListActive — currently running ads (started, not yet ended, is_active flag on) for the feed.
// Visible to every authenticated role alike — the feature has no per-role visibility rule.
func (r *AdvertisementRepository) ListActive(ctx context.Context) ([]models.Advertisement, error) {
	query := fmt.Sprintf(`SELECT %s FROM advertisements a JOIN users u ON u.id = a.advertiser_id
		WHERE a.is_active = true AND a.starts_at <= now() AND (a.ends_at IS NULL OR a.ends_at > now())
		ORDER BY a.created_at DESC`, adColumns)
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Advertisement
	for rows.Next() {
		a, err := scanAd(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (r *AdvertisementRepository) ListByAdvertiser(ctx context.Context, advertiserID string) ([]models.Advertisement, error) {
	query := fmt.Sprintf(`SELECT %s FROM advertisements a JOIN users u ON u.id = a.advertiser_id
		WHERE a.advertiser_id = $1 ORDER BY a.created_at DESC`, adColumns)
	rows, err := r.db.Query(ctx, query, advertiserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Advertisement
	for rows.Next() {
		a, err := scanAd(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// GetByID — used by the Advertisement Details screen; not scoped to any particular viewer
// since ListActive already establishes "every ad is visible to every role".
func (r *AdvertisementRepository) GetByID(ctx context.Context, id string) (*models.Advertisement, error) {
	query := fmt.Sprintf(`SELECT %s FROM advertisements a JOIN users u ON u.id = a.advertiser_id WHERE a.id = $1`, adColumns)
	a, err := scanAd(r.db.QueryRow(ctx, query, id))
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &a, nil
}

func (r *AdvertisementRepository) IncrementViews(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `UPDATE advertisements SET views = views + 1 WHERE id = $1`, id)
	return err
}

// Update — advertiser-scoped: the WHERE clause requires ownership, so a caller can never edit
// another user's ad even if they somehow guessed the ID.
func (r *AdvertisementRepository) Update(ctx context.Context, id, advertiserID string, a *models.Advertisement) (bool, error) {
	tag, err := r.db.Exec(ctx, `UPDATE advertisements SET
			title = $1, description = $2, category = $3, media_type = $4, image_url = $5,
			price = $6, contact_info = $7, target_url = $8, ends_at = $9
		WHERE id = $10 AND advertiser_id = $11`,
		a.Title, a.Description, a.Category, a.MediaType, a.ImageURL, a.Price, a.ContactInfo, a.TargetURL, a.EndsAt, id, advertiserID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// SetActive — advertiser-scoped publish/unpublish toggle.
func (r *AdvertisementRepository) SetActive(ctx context.Context, id, advertiserID string, active bool) (bool, error) {
	tag, err := r.db.Exec(ctx, `UPDATE advertisements SET is_active = $1 WHERE id = $2 AND advertiser_id = $3`, active, id, advertiserID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// Delete — advertiser-scoped.
func (r *AdvertisementRepository) Delete(ctx context.Context, id, advertiserID string) (bool, error) {
	tag, err := r.db.Exec(ctx, `DELETE FROM advertisements WHERE id = $1 AND advertiser_id = $2`, id, advertiserID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}
