package models

import "time"

type Company struct {
	ID                    string    `json:"id" db:"id"`
	UserID                string    `json:"user_id" db:"user_id"`
	CompanyName           string    `json:"company_name" db:"company_name"`
	BusinessType          *string   `json:"business_type,omitempty" db:"business_type"`
	RegistrationNumber    *string   `json:"registration_number,omitempty" db:"registration_number"`
	Address               *string   `json:"address,omitempty" db:"address"`
	City                  *string   `json:"city,omitempty" db:"city"`
	Country               *string   `json:"country,omitempty" db:"country"`
	Website               *string   `json:"website,omitempty" db:"website"`
	ProductsImported      *string   `json:"products_imported,omitempty" db:"products_imported"`
	PreferredShippingMode *string   `json:"preferred_shipping_mode,omitempty" db:"preferred_shipping_mode"`
	Certifications        []string  `json:"certifications" db:"certifications"`
	CreatedAt             time.Time `json:"created_at" db:"created_at"`
	UpdatedAt             time.Time `json:"updated_at" db:"updated_at"`
}

// DirectoryListing — a row in the importer-facing supplier directory (Journey 3). Trimmed
// compared to the full profile: enough to browse/search and decide whether to open the profile.
type DirectoryListing struct {
	CompanyID    string   `json:"company_id"`
	UserID       string   `json:"user_id"`
	CompanyName  string   `json:"company_name"`
	City         *string  `json:"city,omitempty"`
	Country      *string  `json:"country,omitempty"`
	BusinessType *string  `json:"business_type,omitempty"`
	AvgRating    *float64 `json:"avg_rating,omitempty"`
	RatingCount  int      `json:"rating_count"`
	ProductCount int      `json:"product_count"`
}

// CompanyProfile — the full public profile behind "open company profile" (Journey 3):
// company details, certifications, products, ratings, and average response time.
type CompanyProfile struct {
	Company              Company   `json:"company"`
	AvgRating            *float64  `json:"avg_rating,omitempty"`
	RatingCount          int       `json:"rating_count"`
	AvgResponseTimeHours *float64  `json:"avg_response_time_hours,omitempty"`
	Products             []Product `json:"products"`
}

type CompanyRating struct {
	ID        string    `json:"id" db:"id"`
	CompanyID string    `json:"company_id" db:"company_id"`
	OrderID   string    `json:"order_id" db:"order_id"`
	RatedBy   string    `json:"rated_by" db:"rated_by"`
	Score     int       `json:"score" db:"score"`
	Comment   *string   `json:"comment,omitempty" db:"comment"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}
