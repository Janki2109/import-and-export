package models

import "time"

type OrderStatus string

const (
	OrderCreated         OrderStatus = "created"
	OrderPaymentHeld     OrderStatus = "payment_held"
	OrderAccepted        OrderStatus = "accepted"
	OrderShipped         OrderStatus = "shipped"
	OrderInTransit       OrderStatus = "in_transit"
	OrderDelivered       OrderStatus = "delivered"
	OrderConfirmed       OrderStatus = "confirmed"
	OrderPaymentReleased OrderStatus = "payment_released"
	OrderDisputed        OrderStatus = "disputed"
	OrderCancelled       OrderStatus = "cancelled"
	OrderRefunded        OrderStatus = "refunded"
)

type PaymentStatus string

const (
	PaymentCreated    PaymentStatus = "created"
	PaymentAuthorized PaymentStatus = "authorized"
	PaymentHeld       PaymentStatus = "held"
	PaymentOnHold     PaymentStatus = "on_hold"
	PaymentReleased   PaymentStatus = "released"
	PaymentRefunded   PaymentStatus = "refunded"
	PaymentFailed     PaymentStatus = "failed"
)

type ShipmentStatus string

const (
	ShipmentPending              ShipmentStatus = "pending"
	ShipmentAssigned             ShipmentStatus = "assigned"
	ShipmentPickupScheduled      ShipmentStatus = "pickup_scheduled"
	ShipmentPickedUp             ShipmentStatus = "picked_up"
	ShipmentAtWarehouse          ShipmentStatus = "at_warehouse"
	ShipmentCustomsClearance     ShipmentStatus = "customs_clearance"
	ShipmentLoaded               ShipmentStatus = "loaded"
	ShipmentInTransit            ShipmentStatus = "in_transit"
	ShipmentArrivedAtDestination ShipmentStatus = "arrived_at_destination"
	ShipmentOutForDelivery       ShipmentStatus = "out_for_delivery"
	ShipmentDelivered            ShipmentStatus = "delivered"
	ShipmentException            ShipmentStatus = "exception"
)

type Order struct {
	ID                   string      `json:"id" db:"id"`
	OrderNumber          string      `json:"order_number" db:"order_number"`
	ImporterID           string      `json:"importer_id" db:"importer_id"`
	ExporterID           string      `json:"exporter_id" db:"exporter_id"`
	ProductName          string      `json:"product_name" db:"product_name"`
	HSNCode              *string     `json:"hsn_code,omitempty" db:"hsn_code"`
	Quantity             float64     `json:"quantity" db:"quantity"`
	Unit                 string      `json:"unit" db:"unit"`
	UnitPrice            float64     `json:"unit_price" db:"unit_price"`
	Currency             string      `json:"currency" db:"currency"`
	TotalAmount          float64     `json:"total_amount" db:"total_amount"`
	PlatformFeePercent   float64     `json:"platform_fee_percent" db:"platform_fee_percent"`
	PlatformFeeAmount    float64     `json:"platform_fee_amount" db:"platform_fee_amount"`
	ExporterPayoutAmount float64     `json:"exporter_payout_amount" db:"exporter_payout_amount"`
	Status               OrderStatus `json:"status" db:"status"`
	AutoReleaseDays      int         `json:"auto_release_days" db:"auto_release_days"`
	DeliveryAddress      *string     `json:"delivery_address,omitempty" db:"delivery_address"`
	Notes                *string     `json:"notes,omitempty" db:"notes"`
	CreatedAt            time.Time   `json:"created_at" db:"created_at"`
	UpdatedAt            time.Time   `json:"updated_at" db:"updated_at"`
}

type EscrowPayment struct {
	ID                string        `json:"id" db:"id"`
	OrderID           string        `json:"order_id" db:"order_id"`
	RazorpayOrderID   *string       `json:"razorpay_order_id,omitempty" db:"razorpay_order_id"`
	RazorpayPaymentID *string       `json:"razorpay_payment_id,omitempty" db:"razorpay_payment_id"`
	RazorpayPayoutID  *string       `json:"razorpay_payout_id,omitempty" db:"razorpay_payout_id"`
	Amount            float64       `json:"amount" db:"amount"`
	PlatformFee       float64       `json:"platform_fee" db:"platform_fee"`
	PayoutAmount      float64       `json:"payout_amount" db:"payout_amount"`
	Status            PaymentStatus `json:"status" db:"status"`
	HeldAt            *time.Time    `json:"held_at,omitempty" db:"held_at"`
	ReleaseDueAt      *time.Time    `json:"release_due_at,omitempty" db:"release_due_at"`
	ReleasedAt        *time.Time    `json:"released_at,omitempty" db:"released_at"`
	RefundedAt        *time.Time    `json:"refunded_at,omitempty" db:"refunded_at"`
	AdminNotifiedAt   *time.Time    `json:"admin_notified_at,omitempty" db:"admin_notified_at"`
	FailureReason     *string       `json:"failure_reason,omitempty" db:"failure_reason"`
	CreatedAt         time.Time     `json:"created_at" db:"created_at"`
	UpdatedAt         time.Time     `json:"updated_at" db:"updated_at"`
}

type Shipment struct {
	ID                string         `json:"id" db:"id"`
	OrderID           string         `json:"order_id" db:"order_id"`
	LogisticsID       *string        `json:"logistics_id,omitempty" db:"logistics_id"`
	TrackingNumber    *string        `json:"tracking_number,omitempty" db:"tracking_number"`
	Status            ShipmentStatus `json:"status" db:"status"`
	PickupAddress     *string        `json:"pickup_address,omitempty" db:"pickup_address"`
	DeliveryAddress   *string        `json:"delivery_address,omitempty" db:"delivery_address"`
	CarrierName       *string        `json:"carrier_name,omitempty" db:"carrier_name"`
	EstimatedDelivery *time.Time     `json:"estimated_delivery,omitempty" db:"estimated_delivery"`
	PickedUpAt        *time.Time     `json:"picked_up_at,omitempty" db:"picked_up_at"`
	DeliveredAt       *time.Time     `json:"delivered_at,omitempty" db:"delivered_at"`
	CreatedAt         time.Time      `json:"created_at" db:"created_at"`
	UpdatedAt         time.Time      `json:"updated_at" db:"updated_at"`
}

type PODDocument struct {
	ID           string    `json:"id" db:"id"`
	ShipmentID   string    `json:"shipment_id" db:"shipment_id"`
	UploadedBy   string    `json:"uploaded_by" db:"uploaded_by"`
	FileURL      string    `json:"file_url" db:"file_url"`
	FileType     string    `json:"file_type" db:"file_type"`
	SignatureURL *string   `json:"signature_url,omitempty" db:"signature_url"`
	Remarks      *string   `json:"remarks,omitempty" db:"remarks"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
}

// WithdrawalRequest — Journey 5: a withdrawal request that stays pending (no ledger effect at
// all) until an admin approves it, at which point the actual debit ledger entry is created.
type WithdrawalRequest struct {
	ID              string     `json:"id" db:"id"`
	UserID          string     `json:"user_id" db:"user_id"`
	Amount          float64    `json:"amount" db:"amount"`
	Status          string     `json:"status" db:"status"` // pending | paid | rejected
	LedgerEntryID   *string    `json:"ledger_entry_id,omitempty" db:"ledger_entry_id"`
	ProcessedBy     *string    `json:"processed_by,omitempty" db:"processed_by"`
	ProcessedAt     *time.Time `json:"processed_at,omitempty" db:"processed_at"`
	RejectionReason *string    `json:"rejection_reason,omitempty" db:"rejection_reason"`
	CreatedAt       time.Time  `json:"created_at" db:"created_at"`
}

type LedgerEntry struct {
	ID           string    `json:"id" db:"id"`
	OrderID      *string   `json:"order_id,omitempty" db:"order_id"`
	UserID       *string   `json:"user_id,omitempty" db:"user_id"`
	EntryType    string    `json:"entry_type" db:"entry_type"` // credit/debit
	Amount       float64   `json:"amount" db:"amount"`
	BalanceAfter *float64  `json:"balance_after,omitempty" db:"balance_after"`
	Description  string    `json:"description" db:"description"`
	ReferenceID  *string   `json:"reference_id,omitempty" db:"reference_id"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
}
