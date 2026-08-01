package models

import "time"

type Company struct {
	ID                 string    `json:"id" db:"id"`
	UserID             string    `json:"user_id" db:"user_id"`
	CompanyName        string    `json:"company_name" db:"company_name"`
	BusinessType       *string   `json:"business_type,omitempty" db:"business_type"`
	RegistrationNumber *string   `json:"registration_number,omitempty" db:"registration_number"`
	Address            *string   `json:"address,omitempty" db:"address"`
	City               *string   `json:"city,omitempty" db:"city"`
	Country            *string   `json:"country,omitempty" db:"country"`
	Website            *string   `json:"website,omitempty" db:"website"`
	ProductsImported   *string   `json:"products_imported,omitempty" db:"products_imported"`
	PreferredShippingMode *string `json:"preferred_shipping_mode,omitempty" db:"preferred_shipping_mode"`
	CreatedAt          time.Time `json:"created_at" db:"created_at"`
	UpdatedAt          time.Time `json:"updated_at" db:"updated_at"`
}
