package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type RatingRepository struct {
	db *pgxpool.Pool
}

func NewRatingRepository(db *pgxpool.Pool) *RatingRepository {
	return &RatingRepository{db: db}
}

func (r *RatingRepository) Create(ctx context.Context, rating *models.CompanyRating) error {
	query := `INSERT INTO company_ratings (company_id, order_id, rated_by, score, comment)
		VALUES ($1,$2,$3,$4,$5)
		RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, rating.CompanyID, rating.OrderID, rating.RatedBy, rating.Score, rating.Comment).
		Scan(&rating.ID, &rating.CreatedAt)
}

func (r *RatingRepository) ListByCompany(ctx context.Context, companyID string, limit, offset int) ([]models.CompanyRating, error) {
	rows, err := r.db.Query(ctx, `SELECT id, company_id, order_id, rated_by, score, comment, created_at
		FROM company_ratings WHERE company_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`, companyID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.CompanyRating
	for rows.Next() {
		var rt models.CompanyRating
		if err := rows.Scan(&rt.ID, &rt.CompanyID, &rt.OrderID, &rt.RatedBy, &rt.Score, &rt.Comment, &rt.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, rt)
	}
	return out, rows.Err()
}
