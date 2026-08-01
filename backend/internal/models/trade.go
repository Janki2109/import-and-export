package models

import "time"

type RFQStatus string

const (
	RFQOpen     RFQStatus = "open"
	RFQQuoted   RFQStatus = "quoted"
	RFQClosed   RFQStatus = "closed"
	RFQCancelled RFQStatus = "cancelled"
)

type QuotationStatus string

const (
	QuotationPending  QuotationStatus = "pending"
	QuotationAccepted QuotationStatus = "accepted"
	QuotationRejected QuotationStatus = "rejected"
	QuotationExpired  QuotationStatus = "expired"
)

type DocumentType string

const (
	DocCommercialInvoice   DocumentType = "commercial_invoice"
	DocPackingList         DocumentType = "packing_list"
	DocCertificateOfOrigin DocumentType = "certificate_of_origin"
	DocBillOfLading        DocumentType = "bill_of_lading"
	DocAirWaybill          DocumentType = "air_waybill"
	DocShippingInvoice     DocumentType = "shipping_invoice"
)

type RFQ struct {
	ID                  string    `json:"id" db:"id"`
	RFQNumber           string    `json:"rfq_number" db:"rfq_number"`
	ImporterID          string    `json:"importer_id" db:"importer_id"`
	ProductName         string    `json:"product_name" db:"product_name"`
	HSNCode             *string   `json:"hsn_code,omitempty" db:"hsn_code"`
	Quantity            float64   `json:"quantity" db:"quantity"`
	Unit                string    `json:"unit" db:"unit"`
	TargetPrice         *float64  `json:"target_price,omitempty" db:"target_price"`
	DestinationCountry  string    `json:"destination_country" db:"destination_country"`
	Description         *string   `json:"description,omitempty" db:"description"`
	Status              RFQStatus `json:"status" db:"status"`
	CreatedAt           time.Time `json:"created_at" db:"created_at"`
	UpdatedAt           time.Time `json:"updated_at" db:"updated_at"`
}

type Quotation struct {
	ID           string          `json:"id" db:"id"`
	RFQID        string          `json:"rfq_id" db:"rfq_id"`
	ExporterID   string          `json:"exporter_id" db:"exporter_id"`
	UnitPrice    float64         `json:"unit_price" db:"unit_price"`
	Quantity     float64         `json:"quantity" db:"quantity"`
	TotalAmount  float64         `json:"total_amount" db:"total_amount"`
	ValidityDate time.Time       `json:"validity_date" db:"validity_date"`
	Terms        *string         `json:"terms,omitempty" db:"terms"`
	Status       QuotationStatus `json:"status" db:"status"`
	OrderID      *string         `json:"order_id,omitempty" db:"order_id"`
	CreatedAt    time.Time       `json:"created_at" db:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at" db:"updated_at"`
}

type Document struct {
	ID          string       `json:"id" db:"id"`
	OrderID     string       `json:"order_id" db:"order_id"`
	Type        DocumentType `json:"type" db:"type"`
	FileURL     string       `json:"file_url" db:"file_url"`
	GeneratedBy string       `json:"generated_by" db:"generated_by"`
	CreatedAt   time.Time    `json:"created_at" db:"created_at"`
}
