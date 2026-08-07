package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type DirectoryRepository struct {
	db *pgxpool.Pool
}

func NewDirectoryRepository(db *pgxpool.Pool) *DirectoryRepository {
	return &DirectoryRepository{db: db}
}

// ListLogisticsPartners — "Find Logistics Partner" directory: active logistics users,
// with company profile (if completed) and KYC-verified status so exporters can judge
// trustworthiness before sending a shipment request. query filters by name/company/city/country.
func (r *DirectoryRepository) ListLogisticsPartners(ctx context.Context, query string) ([]models.LogisticsPartner, error) {
	// BUG FIX (H-22): (k.status = 'verified') over a LEFT JOIN yields SQL NULL for any account
	// with no kyc_details row (every newly-registered logistics account, until they submit KYC)
	// — pgx cannot scan NULL into models.LogisticsPartner.KYCVerified's non-pointer bool, so
	// this query errored out entirely for ALL callers the moment even one such account existed,
	// killing the whole "Find Logistics Partner" screen. COALESCE to false fixes the scan; NULLS
	// LAST (equivalent here since COALESCE removes the NULL, but kept explicit) ensures
	// unverified partners don't rank above verified ones by accident of NULL-sort-order.
	sql := `
		SELECT u.id, u.full_name, c.company_name, c.city, c.country,
			COALESCE(k.status = 'verified', false) AS kyc_verified,
			COALESCE(ARRAY_AGG(DISTINCT f.vehicle_type) FILTER (WHERE f.vehicle_type IS NOT NULL), '{}')
		FROM users u
		LEFT JOIN companies c ON c.user_id = u.id
		LEFT JOIN kyc_details k ON k.user_id = u.id
		LEFT JOIN fleet_vehicles f ON f.logistics_id = u.id AND f.status = 'active'
		WHERE u.role = 'logistics' AND u.is_active = true
		  AND ($1 = '' OR u.full_name ILIKE '%' || $1 || '%' OR c.company_name ILIKE '%' || $1 || '%'
		       OR c.city ILIKE '%' || $1 || '%' OR c.country ILIKE '%' || $1 || '%')
		GROUP BY u.id, u.full_name, c.company_name, c.city, c.country, k.status
		ORDER BY kyc_verified DESC NULLS LAST, u.full_name`

	rows, err := r.db.Query(ctx, sql, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.LogisticsPartner
	for rows.Next() {
		var p models.LogisticsPartner
		if err := rows.Scan(&p.UserID, &p.FullName, &p.CompanyName, &p.City, &p.Country, &p.KYCVerified, &p.VehicleTypes); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, nil
}
