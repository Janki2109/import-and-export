package models

// LogisticsPartner — "Find Logistics Partner" directory entry (exporter-facing).
type LogisticsPartner struct {
	UserID       string   `json:"user_id"`
	FullName     string   `json:"full_name"`
	CompanyName  *string  `json:"company_name,omitempty"`
	City         *string  `json:"city,omitempty"`
	Country      *string  `json:"country,omitempty"`
	KYCVerified  bool     `json:"kyc_verified"`
	VehicleTypes []string `json:"vehicle_types,omitempty"`
}
