package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type CompanyRepository struct {
	db *pgxpool.Pool
}

func NewCompanyRepository(db *pgxpool.Pool) *CompanyRepository {
	return &CompanyRepository{db: db}
}

func (r *CompanyRepository) GetByUserID(ctx context.Context, userID string) (*models.Company, error) {
	query := `SELECT id, user_id, company_name, business_type, registration_number, address, city, country, website,
		products_imported, preferred_shipping_mode, created_at, updated_at
		FROM companies WHERE user_id = $1`
	var c models.Company
	err := r.db.QueryRow(ctx, query, userID).Scan(
		&c.ID, &c.UserID, &c.CompanyName, &c.BusinessType, &c.RegistrationNumber, &c.Address, &c.City, &c.Country, &c.Website,
		&c.ProductsImported, &c.PreferredShippingMode, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}

// Upsert — "Create Company" onboarding step; also usable later for editing the profile.
func (r *CompanyRepository) Upsert(ctx context.Context, c *models.Company) error {
	query := `INSERT INTO companies (user_id, company_name, business_type, registration_number, address, city, country, website, products_imported, preferred_shipping_mode)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		ON CONFLICT (user_id) DO UPDATE SET
			company_name = EXCLUDED.company_name, business_type = EXCLUDED.business_type,
			registration_number = EXCLUDED.registration_number, address = EXCLUDED.address,
			city = EXCLUDED.city, country = EXCLUDED.country, website = EXCLUDED.website,
			products_imported = EXCLUDED.products_imported, preferred_shipping_mode = EXCLUDED.preferred_shipping_mode
		RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query, c.UserID, c.CompanyName, c.BusinessType, c.RegistrationNumber, c.Address, c.City, c.Country, c.Website, c.ProductsImported, c.PreferredShippingMode).
		Scan(&c.ID, &c.CreatedAt, &c.UpdatedAt)
}
