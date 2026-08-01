package models

import "time"

type HSCode struct {
	ID                       string    `json:"id" db:"id"`
	Code                     string    `json:"code" db:"code"`
	Description              string    `json:"description" db:"description"`
	Chapter                  string    `json:"chapter" db:"chapter"`
	BasicCustomsDutyPercent  float64   `json:"basic_customs_duty_percent" db:"basic_customs_duty_percent"`
	IGSTPercent              float64   `json:"igst_percent" db:"igst_percent"`
	CreatedAt                time.Time `json:"created_at" db:"created_at"`
}

type GSTRate struct {
	ID          string    `json:"id" db:"id"`
	Category    string    `json:"category" db:"category"`
	RatePercent float64   `json:"rate_percent" db:"rate_percent"`
	Description *string   `json:"description,omitempty" db:"description"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}

type Country struct {
	ID           string    `json:"id" db:"id"`
	Name         string    `json:"name" db:"name"`
	ISO2         string    `json:"iso2" db:"iso2"`
	ISO3         string    `json:"iso3" db:"iso3"`
	Region       string    `json:"region" db:"region"`
	IsRestricted bool      `json:"is_restricted" db:"is_restricted"`
	Notes        *string   `json:"notes,omitempty" db:"notes"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
}

type TradePolicy struct {
	ID          string    `json:"id" db:"id"`
	CountryID   *string   `json:"country_id,omitempty" db:"country_id"`
	PolicyType  string    `json:"policy_type" db:"policy_type"`
	HSChapter   *string   `json:"hs_chapter,omitempty" db:"hs_chapter"`
	Title       string    `json:"title" db:"title"`
	Description string    `json:"description" db:"description"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}
