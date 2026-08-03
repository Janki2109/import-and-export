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
		products_imported, preferred_shipping_mode, certifications, created_at, updated_at
		FROM companies WHERE user_id = $1`
	var c models.Company
	err := r.db.QueryRow(ctx, query, userID).Scan(
		&c.ID, &c.UserID, &c.CompanyName, &c.BusinessType, &c.RegistrationNumber, &c.Address, &c.City, &c.Country, &c.Website,
		&c.ProductsImported, &c.PreferredShippingMode, &c.Certifications, &c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}

func (r *CompanyRepository) GetByID(ctx context.Context, companyID string) (*models.Company, error) {
	query := `SELECT id, user_id, company_name, business_type, registration_number, address, city, country, website,
		products_imported, preferred_shipping_mode, certifications, created_at, updated_at
		FROM companies WHERE id = $1`
	var c models.Company
	err := r.db.QueryRow(ctx, query, companyID).Scan(
		&c.ID, &c.UserID, &c.CompanyName, &c.BusinessType, &c.RegistrationNumber, &c.Address, &c.City, &c.Country, &c.Website,
		&c.ProductsImported, &c.PreferredShippingMode, &c.Certifications, &c.CreatedAt, &c.UpdatedAt,
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
	query := `INSERT INTO companies (user_id, company_name, business_type, registration_number, address, city, country, website, products_imported, preferred_shipping_mode, certifications)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		ON CONFLICT (user_id) DO UPDATE SET
			company_name = EXCLUDED.company_name, business_type = EXCLUDED.business_type,
			registration_number = EXCLUDED.registration_number, address = EXCLUDED.address,
			city = EXCLUDED.city, country = EXCLUDED.country, website = EXCLUDED.website,
			products_imported = EXCLUDED.products_imported, preferred_shipping_mode = EXCLUDED.preferred_shipping_mode,
			certifications = EXCLUDED.certifications
		RETURNING id, created_at, updated_at`
	if c.Certifications == nil {
		c.Certifications = []string{}
	}
	return r.db.QueryRow(ctx, query, c.UserID, c.CompanyName, c.BusinessType, c.RegistrationNumber, c.Address, c.City, c.Country, c.Website, c.ProductsImported, c.PreferredShippingMode, c.Certifications).
		Scan(&c.ID, &c.CreatedAt, &c.UpdatedAt)
}

// ListExporterDirectory — Journey 3's supplier directory. Joins users so only companies
// belonging to exporter-role accounts are listed (importers browse exporters, not other
// importers), with an optional free-text search across company name/city/country and average
// rating/product counts so the directory list is useful without opening each profile.
func (r *CompanyRepository) ListExporterDirectory(ctx context.Context, search string, limit, offset int) ([]models.DirectoryListing, error) {
	query := `
		SELECT c.id, c.user_id, c.company_name, c.city, c.country, c.business_type,
			(SELECT AVG(score)::float8 FROM company_ratings cr WHERE cr.company_id = c.id),
			(SELECT COUNT(*) FROM company_ratings cr WHERE cr.company_id = c.id),
			(SELECT COUNT(*) FROM products p WHERE p.exporter_id = c.user_id AND p.is_active = true)
		FROM companies c
		JOIN users u ON u.id = c.user_id AND u.role = 'exporter'
		WHERE ($1 = '' OR c.company_name ILIKE '%' || $1 || '%' OR c.city ILIKE '%' || $1 || '%' OR c.country ILIKE '%' || $1 || '%')
		ORDER BY c.company_name ASC
		LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, search, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.DirectoryListing
	for rows.Next() {
		var d models.DirectoryListing
		if err := rows.Scan(&d.CompanyID, &d.UserID, &d.CompanyName, &d.City, &d.Country, &d.BusinessType,
			&d.AvgRating, &d.RatingCount, &d.ProductCount); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// RatingSummary — average score + count for one company.
func (r *CompanyRepository) RatingSummary(ctx context.Context, companyID string) (*float64, int, error) {
	var avg *float64
	var count int
	err := r.db.QueryRow(ctx, `SELECT AVG(score)::float8, COUNT(*) FROM company_ratings WHERE company_id = $1`, companyID).Scan(&avg, &count)
	if err != nil {
		return nil, 0, err
	}
	return avg, count, nil
}

// AvgResponseTimeHours — average time between an RFQ reaching this exporter (rfq_targets row,
// or the RFQ's own created_at if it was an open/untargeted broadcast) and their quotation on it.
// nil if this exporter has never submitted a quotation.
func (r *CompanyRepository) AvgResponseTimeHours(ctx context.Context, exporterUserID string) (*float64, error) {
	var avgHours *float64
	err := r.db.QueryRow(ctx, `
		SELECT AVG(EXTRACT(EPOCH FROM (q.created_at - COALESCE(rt.created_at, r.created_at))) / 3600.0)::float8
		FROM quotations q
		JOIN rfqs r ON r.id = q.rfq_id
		LEFT JOIN rfq_targets rt ON rt.rfq_id = q.rfq_id AND rt.exporter_id = q.exporter_id
		WHERE q.exporter_id = $1`, exporterUserID).Scan(&avgHours)
	if err != nil {
		return nil, err
	}
	return avgHours, nil
}
