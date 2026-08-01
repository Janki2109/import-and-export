package models

import "time"

type Analytics struct {
	TotalUsers         int            `json:"total_users"`
	TotalImporters     int            `json:"total_importers"`
	TotalExporters     int            `json:"total_exporters"`
	TotalLogistics     int            `json:"total_logistics"`
	TotalOrders        int            `json:"total_orders"`
	TotalGMV           float64        `json:"total_gmv"`
	TotalPlatformFees  float64        `json:"total_platform_fees"`
	OrdersByStatus     map[string]int `json:"orders_by_status"`
	PendingKYCCount    int            `json:"pending_kyc_count"`
	OpenDisputesCount  int            `json:"open_disputes_count"`
}

type FraudSignal struct {
	Type        string    `json:"type"`
	UserID      *string   `json:"user_id,omitempty"`
	Email       *string   `json:"email,omitempty"`
	Description string    `json:"description"`
	Severity    string    `json:"severity"` // low | medium | high
	DetectedAt  time.Time `json:"detected_at"`
}

type LoginAttempt struct {
	ID        string    `json:"id" db:"id"`
	Email     string    `json:"email" db:"email"`
	Success   bool      `json:"success" db:"success"`
	IPAddress *string   `json:"ip_address,omitempty" db:"ip_address"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

type APIKey struct {
	ID         string     `json:"id" db:"id"`
	UserID     string     `json:"user_id" db:"user_id"`
	Label      *string    `json:"label,omitempty" db:"label"`
	LastUsedAt *time.Time `json:"last_used_at,omitempty" db:"last_used_at"`
	Revoked    bool       `json:"revoked" db:"revoked"`
	CreatedAt  time.Time  `json:"created_at" db:"created_at"`
}
