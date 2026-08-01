package models

import "time"

type PaymentModel string

const (
	PaymentModelAdvance100     PaymentModel = "advance_100"
	PaymentModelAdvanceBalance PaymentModel = "advance_balance"
	PaymentModelMilestone      PaymentModel = "milestone_escrow"
	PaymentModelLC             PaymentModel = "letter_of_credit"
	PaymentModelOpenAccount    PaymentModel = "open_account"
	PaymentModelCustom         PaymentModel = "custom"
)

type PaymentMilestoneStatus string

const (
	MilestonePending         PaymentMilestoneStatus = "pending"
	MilestonePaid            PaymentMilestoneStatus = "paid"
	MilestoneWaitingApproval PaymentMilestoneStatus = "waiting_approval"
	MilestoneApproved        PaymentMilestoneStatus = "approved"
	MilestoneReleased        PaymentMilestoneStatus = "released"
	MilestoneRejected        PaymentMilestoneStatus = "rejected"
	MilestoneOnHold          PaymentMilestoneStatus = "on_hold"
)

type LCStatus string

const (
	LCIssued    LCStatus = "issued"
	LCPending   LCStatus = "pending"
	LCVerified  LCStatus = "verified"
	LCCompleted LCStatus = "completed"
)

// PaymentTerms — one per order (1:1), locked once created; the negotiated payment model
// for that order.
type PaymentTerms struct {
	ID              string       `json:"id" db:"id"`
	OrderID         string       `json:"order_id" db:"order_id"`
	PaymentModel    PaymentModel `json:"payment_model" db:"payment_model"`
	Currency        string       `json:"currency" db:"currency"`
	TotalAmount     float64      `json:"total_amount" db:"total_amount"`
	LCNumber        *string      `json:"lc_number,omitempty" db:"lc_number"`
	LCBankName      *string      `json:"lc_bank_name,omitempty" db:"lc_bank_name"`
	LCExpiryDate    *time.Time   `json:"lc_expiry_date,omitempty" db:"lc_expiry_date"`
	LCStatus        *LCStatus    `json:"lc_status,omitempty" db:"lc_status"`
	OpenAccountDays *int         `json:"open_account_days,omitempty" db:"open_account_days"`
	Status          string       `json:"status" db:"status"`
	CreatedBy       string       `json:"created_by" db:"created_by"`
	CreatedAt       time.Time    `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time    `json:"updated_at" db:"updated_at"`
}

// PaymentMilestone — one release tranche under a PaymentTerms row.
type PaymentMilestone struct {
	ID              string                 `json:"id" db:"id"`
	PaymentTermID   string                 `json:"payment_term_id" db:"payment_term_id"`
	ReleaseOrder    int                    `json:"release_order" db:"release_order"`
	Title           string                 `json:"title" db:"title"`
	Percentage      float64                `json:"percentage" db:"percentage"`
	Amount          float64                `json:"amount" db:"amount"`
	Status          PaymentMilestoneStatus `json:"status" db:"status"`
	TriggerEvent    string                 `json:"trigger_event" db:"trigger_event"`
	ProofRequired   bool                   `json:"proof_required" db:"proof_required"`
	ProofURL        *string                `json:"proof_url,omitempty" db:"proof_url"`
	ProofUploadedAt *time.Time             `json:"proof_uploaded_at,omitempty" db:"proof_uploaded_at"`
	UploadedBy      *string                `json:"uploaded_by,omitempty" db:"uploaded_by"`
	PaidAt          *time.Time             `json:"paid_at,omitempty" db:"paid_at"`
	ReviewedBy      *string                `json:"reviewed_by,omitempty" db:"reviewed_by"`
	ReviewedAt      *time.Time             `json:"reviewed_at,omitempty" db:"reviewed_at"`
	Remarks         *string                `json:"remarks,omitempty" db:"remarks"`
	ReleasedAt      *time.Time             `json:"released_at,omitempty" db:"released_at"`
	CreatedAt       time.Time              `json:"created_at" db:"created_at"`
	UpdatedAt       time.Time              `json:"updated_at" db:"updated_at"`
}
