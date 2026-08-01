package models

import "time"

// ComplianceStatus — lifecycle of a single document within an order's compliance checklist.
type ComplianceStatus string

const (
	CompliancePending  ComplianceStatus = "pending"
	ComplianceUploaded ComplianceStatus = "uploaded"
	ComplianceVerified ComplianceStatus = "verified"
	ComplianceRejected ComplianceStatus = "rejected"
)

// ComplianceRule — a single row in the database-driven rule engine. Any of
// OriginCountry/DestinationCountry/HSCode/ShippingMode may be nil, meaning "applies
// regardless of this dimension" — this is what lets new trade routes be supported by
// inserting rows alone, with zero application code changes.
type ComplianceRule struct {
	ID                 string    `json:"id" db:"id"`
	OriginCountry      *string   `json:"origin_country,omitempty" db:"origin_country"`
	DestinationCountry *string   `json:"destination_country,omitempty" db:"destination_country"`
	HSCode             *string   `json:"hs_code,omitempty" db:"hs_code"`
	ShippingMode       *string   `json:"shipping_mode,omitempty" db:"shipping_mode"`
	DocumentName       string    `json:"document_name" db:"document_name"`
	ResponsibleRole    UserRole  `json:"responsible_role" db:"responsible_role"`
	Mandatory          bool      `json:"mandatory" db:"mandatory"`
	DisplayOrder       int       `json:"display_order" db:"display_order"`
	Description        *string   `json:"description,omitempty" db:"description"`
	CreatedAt          time.Time `json:"created_at" db:"created_at"`
}

// OrderCompliance — one checklist item, copied from a matching ComplianceRule at order
// creation time (see ComplianceService.GenerateChecklist).
type OrderCompliance struct {
	ID              string           `json:"id" db:"id"`
	OrderID         string           `json:"order_id" db:"order_id"`
	RuleID          *string          `json:"rule_id,omitempty" db:"rule_id"`
	DocumentName    string           `json:"document_name" db:"document_name"`
	ResponsibleRole UserRole         `json:"responsible_role" db:"responsible_role"`
	Mandatory       bool             `json:"mandatory" db:"mandatory"`
	DisplayOrder    int              `json:"display_order" db:"display_order"`
	Description     *string          `json:"description,omitempty" db:"description"`
	Status          ComplianceStatus `json:"status" db:"status"`
	UploadedFile    *string          `json:"uploaded_file,omitempty" db:"uploaded_file"`
	Remarks         *string          `json:"remarks,omitempty" db:"remarks"`
	VerifiedByAdmin *string          `json:"verified_by_admin,omitempty" db:"verified_by_admin"`
	UploadedAt      *time.Time       `json:"uploaded_at,omitempty" db:"uploaded_at"`
	VerifiedAt      *time.Time       `json:"verified_at,omitempty" db:"verified_at"`
	CreatedAt       time.Time        `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time        `json:"updated_at" db:"updated_at"`
}

// ComplianceDocumentHistory — one row per upload/re-upload of a checklist item, so a
// rejected-then-reuploaded document keeps its full version history.
type ComplianceDocumentHistory struct {
	ID                string    `json:"id" db:"id"`
	OrderComplianceID string    `json:"order_compliance_id" db:"order_compliance_id"`
	FileURL           string    `json:"file_url" db:"file_url"`
	UploadedBy        string    `json:"uploaded_by" db:"uploaded_by"`
	Remarks           *string   `json:"remarks,omitempty" db:"remarks"`
	CreatedAt         time.Time `json:"created_at" db:"created_at"`
}
