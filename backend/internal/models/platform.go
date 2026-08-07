package models

import "time"

type VehicleStatus string

const (
	VehicleActive      VehicleStatus = "active"
	VehicleInactive    VehicleStatus = "inactive"
	VehicleMaintenance VehicleStatus = "maintenance"
)

type FleetVehicle struct {
	ID                 string        `json:"id" db:"id"`
	LogisticsID        string        `json:"logistics_id" db:"logistics_id"`
	VehicleType        string        `json:"vehicle_type" db:"vehicle_type"`
	RegistrationNumber string        `json:"registration_number" db:"registration_number"`
	CapacityKg         *float64      `json:"capacity_kg,omitempty" db:"capacity_kg"`
	CapacityCBM        *float64      `json:"capacity_cbm,omitempty" db:"capacity_cbm"`
	ServiceRoute       *string       `json:"service_route,omitempty" db:"service_route"`
	Status             VehicleStatus `json:"status" db:"status"`
	CreatedAt          time.Time     `json:"created_at" db:"created_at"`
	UpdatedAt          time.Time     `json:"updated_at" db:"updated_at"`
}

type Product struct {
	ID          string    `json:"id" db:"id"`
	ExporterID  string    `json:"exporter_id" db:"exporter_id"`
	Name        string    `json:"name" db:"name"`
	HSNCode     *string   `json:"hsn_code,omitempty" db:"hsn_code"`
	Description *string   `json:"description,omitempty" db:"description"`
	Unit        string    `json:"unit" db:"unit"`
	UnitPrice   float64   `json:"unit_price" db:"unit_price"`
	MinOrderQty float64   `json:"min_order_qty" db:"min_order_qty"`
	ImageURL    *string   `json:"image_url,omitempty" db:"image_url"`
	IsActive    bool      `json:"is_active" db:"is_active"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time `json:"updated_at" db:"updated_at"`
}

type MembershipTier string

const (
	MembershipFree       MembershipTier = "free"
	MembershipPremium    MembershipTier = "premium"    // legacy tier, kept for backward compatibility
	MembershipSilver     MembershipTier = "silver"     // unlimited RFQ
	MembershipGold       MembershipTier = "gold"       // + priority search
	MembershipEnterprise MembershipTier = "enterprise" // + dedicated manager & API access
)

type Membership struct {
	ID string `json:"id" db:"id"`
	UserID string `json:"user_id" db:"user_id"`
	Tier       MembershipTier `json:"tier" db:"tier"`
	IsFeatured bool           `json:"is_featured" db:"is_featured"`
	ExpiresAt  *time.Time     `json:"expires_at,omitempty" db:"expires_at"`
	// FeaturedExpiresAt — BUG FIX (H-09): featured placement previously shared the tier's own
	// ExpiresAt column, so buying a featured listing extended (and could indefinitely renew) a
	// more expensive subscription tier at the featured-listing price. Tracked separately now.
	FeaturedExpiresAt *time.Time `json:"featured_expires_at,omitempty" db:"featured_expires_at"`
	CreatedAt         time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at" db:"updated_at"`
}

type Advertisement struct {
	ID           string     `json:"id" db:"id"`
	AdvertiserID string     `json:"advertiser_id" db:"advertiser_id"`
	Title        string     `json:"title" db:"title"`
	ImageURL     string     `json:"image_url" db:"image_url"`
	TargetURL    *string    `json:"target_url,omitempty" db:"target_url"`
	IsActive     bool       `json:"is_active" db:"is_active"`
	StartsAt     time.Time  `json:"starts_at" db:"starts_at"`
	EndsAt       *time.Time `json:"ends_at,omitempty" db:"ends_at"`
	CreatedAt    time.Time  `json:"created_at" db:"created_at"`
}

// PlatformSettings — singleton row (id=1) editable from the Admin Settings screen.
// SMTPPassword is deliberately json:"-" (never returned to the client); the handler
// reports only whether it's set, via a separate boolean field on the response DTO.
type PlatformSettings struct {
	AppName      string    `json:"app_name" db:"app_name"`
	LogoURL      *string   `json:"logo_url,omitempty" db:"logo_url"`
	SupportEmail *string   `json:"support_email,omitempty" db:"support_email"`
	Currency     string    `json:"currency" db:"currency"`
	SMTPHost     *string   `json:"smtp_host,omitempty" db:"smtp_host"`
	SMTPPort     *int      `json:"smtp_port,omitempty" db:"smtp_port"`
	SMTPUsername *string   `json:"smtp_username,omitempty" db:"smtp_username"`
	SMTPPassword *string   `json:"-" db:"smtp_password"`
	SMTPFrom     *string   `json:"smtp_from,omitempty" db:"smtp_from"`
	UpdatedAt    time.Time `json:"updated_at" db:"updated_at"`
}

type AuditLog struct {
	ID         string    `json:"id" db:"id"`
	ActorID    *string   `json:"actor_id,omitempty" db:"actor_id"`
	Action     string    `json:"action" db:"action"`
	EntityType string    `json:"entity_type" db:"entity_type"`
	EntityID   *string   `json:"entity_id,omitempty" db:"entity_id"`
	Metadata   *string   `json:"metadata,omitempty" db:"metadata"`
	CreatedAt  time.Time `json:"created_at" db:"created_at"`
}
