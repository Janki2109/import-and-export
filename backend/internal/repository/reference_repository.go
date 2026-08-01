package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type ReferenceRepository struct {
	db *pgxpool.Pool
}

func NewReferenceRepository(db *pgxpool.Pool) *ReferenceRepository {
	return &ReferenceRepository{db: db}
}

// SearchHSCodes — matches on code prefix or full-text description search.
func (r *ReferenceRepository) SearchHSCodes(ctx context.Context, query string, limit int) ([]models.HSCode, error) {
	sql := `SELECT id, code, description, chapter, basic_customs_duty_percent, igst_percent, created_at
		FROM hs_codes
		WHERE code ILIKE $1 || '%' OR to_tsvector('english', description) @@ plainto_tsquery('english', $1)
		ORDER BY code LIMIT $2`
	rows, err := r.db.Query(ctx, sql, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.HSCode
	for rows.Next() {
		var h models.HSCode
		if err := rows.Scan(&h.ID, &h.Code, &h.Description, &h.Chapter, &h.BasicCustomsDutyPercent, &h.IGSTPercent, &h.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, nil
}

func (r *ReferenceRepository) GetHSCodeByCode(ctx context.Context, code string) (*models.HSCode, error) {
	sql := `SELECT id, code, description, chapter, basic_customs_duty_percent, igst_percent, created_at
		FROM hs_codes WHERE code = $1`
	var h models.HSCode
	err := r.db.QueryRow(ctx, sql, code).Scan(&h.ID, &h.Code, &h.Description, &h.Chapter, &h.BasicCustomsDutyPercent, &h.IGSTPercent, &h.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &h, nil
}

func (r *ReferenceRepository) ListGSTRates(ctx context.Context) ([]models.GSTRate, error) {
	sql := `SELECT id, category, rate_percent, description, created_at FROM gst_rates ORDER BY rate_percent`
	rows, err := r.db.Query(ctx, sql)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.GSTRate
	for rows.Next() {
		var g models.GSTRate
		if err := rows.Scan(&g.ID, &g.Category, &g.RatePercent, &g.Description, &g.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, nil
}

func (r *ReferenceRepository) SearchCountries(ctx context.Context, query string, limit int) ([]models.Country, error) {
	sql := `SELECT id, name, iso2, iso3, region, is_restricted, notes, created_at
		FROM countries WHERE name ILIKE '%' || $1 || '%' OR iso2 ILIKE $1 OR iso3 ILIKE $1
		ORDER BY name LIMIT $2`
	rows, err := r.db.Query(ctx, sql, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Country
	for rows.Next() {
		var c models.Country
		if err := rows.Scan(&c.ID, &c.Name, &c.ISO2, &c.ISO3, &c.Region, &c.IsRestricted, &c.Notes, &c.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, nil
}

func (r *ReferenceRepository) GetCountryByName(ctx context.Context, name string) (*models.Country, error) {
	sql := `SELECT id, name, iso2, iso3, region, is_restricted, notes, created_at FROM countries WHERE name ILIKE $1`
	var c models.Country
	err := r.db.QueryRow(ctx, sql, name).Scan(&c.ID, &c.Name, &c.ISO2, &c.ISO3, &c.Region, &c.IsRestricted, &c.Notes, &c.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}

// ---------------- Admin: manage reference data ----------------

func (r *ReferenceRepository) CreateHSCode(ctx context.Context, h *models.HSCode) error {
	query := `INSERT INTO hs_codes (code, description, chapter, basic_customs_duty_percent, igst_percent)
		VALUES ($1,$2,$3,$4,$5) RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, h.Code, h.Description, h.Chapter, h.BasicCustomsDutyPercent, h.IGSTPercent).
		Scan(&h.ID, &h.CreatedAt)
}

func (r *ReferenceRepository) DeleteHSCode(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM hs_codes WHERE id = $1`, id)
	return err
}

func (r *ReferenceRepository) CreateCountry(ctx context.Context, c *models.Country) error {
	query := `INSERT INTO countries (name, iso2, iso3, region, is_restricted, notes)
		VALUES ($1,$2,$3,$4,$5,$6) RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, c.Name, c.ISO2, c.ISO3, c.Region, c.IsRestricted, c.Notes).
		Scan(&c.ID, &c.CreatedAt)
}

func (r *ReferenceRepository) SetCountryRestricted(ctx context.Context, id string, restricted bool) error {
	_, err := r.db.Exec(ctx, `UPDATE countries SET is_restricted = $1 WHERE id = $2`, restricted, id)
	return err
}

func (r *ReferenceRepository) DeleteCountry(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM countries WHERE id = $1`, id)
	return err
}

// ListPolicies — filters by country and/or HS chapter (either may be empty to mean "any").
func (r *ReferenceRepository) ListPolicies(ctx context.Context, countryID, hsChapter, policyType string) ([]models.TradePolicy, error) {
	sql := `SELECT id, country_id, policy_type, hs_chapter, title, description, created_at
		FROM trade_policies
		WHERE ($1 = '' OR country_id = $1::uuid OR country_id IS NULL)
		  AND ($2 = '' OR hs_chapter = $2 OR hs_chapter IS NULL)
		  AND ($3 = '' OR policy_type = $3::policy_type)
		ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, sql, countryID, hsChapter, policyType)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.TradePolicy
	for rows.Next() {
		var p models.TradePolicy
		if err := rows.Scan(&p.ID, &p.CountryID, &p.PolicyType, &p.HSChapter, &p.Title, &p.Description, &p.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, nil
}
