package models

import "time"

type NegotiationStatus string

const (
	NegotiationOpen     NegotiationStatus = "open"
	NegotiationAccepted NegotiationStatus = "accepted"
	NegotiationRejected NegotiationStatus = "rejected"
	NegotiationExpired  NegotiationStatus = "expired"
	NegotiationClosed   NegotiationStatus = "closed"
)

type NegotiationOfferStatus string

const (
	OfferPending   NegotiationOfferStatus = "pending"
	OfferAccepted  NegotiationOfferStatus = "accepted"
	OfferRejected  NegotiationOfferStatus = "rejected"
	OfferCountered NegotiationOfferStatus = "countered"
)

type NegotiationParty string

const (
	PartyImporter NegotiationParty = "importer"
	PartyExporter NegotiationParty = "exporter"
)

// Negotiation — one per quotation under negotiation (1:1 with the quotation it's attached to).
type Negotiation struct {
	ID           string            `json:"id" db:"id"`
	RFQID        string            `json:"rfq_id" db:"rfq_id"`
	QuotationID  string            `json:"quotation_id" db:"quotation_id"`
	ImporterID   string            `json:"importer_id" db:"importer_id"`
	ExporterID   string            `json:"exporter_id" db:"exporter_id"`
	Status       NegotiationStatus `json:"status" db:"status"`
	CurrentRound int               `json:"current_round" db:"current_round"`
	CreatedAt    time.Time         `json:"created_at" db:"created_at"`
	UpdatedAt    time.Time         `json:"updated_at" db:"updated_at"`
}

// NegotiationOffer — one entry in the structured timeline (initial quote, each counter
// offer, and the final accepted offer are all rows here).
type NegotiationOffer struct {
	ID                string                 `json:"id" db:"id"`
	NegotiationID     string                 `json:"negotiation_id" db:"negotiation_id"`
	RoundNumber       int                    `json:"round_number" db:"round_number"`
	CreatedBy         NegotiationParty       `json:"created_by" db:"created_by"`
	CreatedByUserID   string                 `json:"created_by_user_id" db:"created_by_user_id"`
	UnitPrice         float64                `json:"unit_price" db:"unit_price"`
	Currency          string                 `json:"currency" db:"currency"`
	Quantity          float64                `json:"quantity" db:"quantity"`
	MOQ               *float64               `json:"moq,omitempty" db:"moq"`
	TotalPrice        float64                `json:"total_price" db:"total_price"`
	DeliveryDays      *int                   `json:"delivery_days,omitempty" db:"delivery_days"`
	DispatchDays      *int                   `json:"dispatch_days,omitempty" db:"dispatch_days"`
	ShippingMode      *string                `json:"shipping_mode,omitempty" db:"shipping_mode"`
	Incoterm          *string                `json:"incoterm,omitempty" db:"incoterm"`
	PaymentTerms      *string                `json:"payment_terms,omitempty" db:"payment_terms"`
	Packaging         *string                `json:"packaging,omitempty" db:"packaging"`
	ValidityDate      *time.Time             `json:"validity_date,omitempty" db:"validity_date"`
	SpecialConditions *string                `json:"special_conditions,omitempty" db:"special_conditions"`
	Remarks           *string                `json:"remarks,omitempty" db:"remarks"`
	Status            NegotiationOfferStatus `json:"status" db:"status"`
	CreatedAt         time.Time              `json:"created_at" db:"created_at"`
}
