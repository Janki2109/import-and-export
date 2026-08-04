package models

import "time"

type RFQStatus string

const (
	RFQOpen      RFQStatus = "open"
	RFQQuoted    RFQStatus = "quoted"
	RFQClosed    RFQStatus = "closed"
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
	DocCommercialInvoice     DocumentType = "commercial_invoice"
	DocPackingList           DocumentType = "packing_list"
	DocCertificateOfOrigin   DocumentType = "certificate_of_origin"
	DocBillOfLading          DocumentType = "bill_of_lading"
	DocAirWaybill            DocumentType = "air_waybill"
	DocShippingInvoice       DocumentType = "shipping_invoice"
	DocExportDeclaration     DocumentType = "export_declaration"
	DocImportDeclaration     DocumentType = "import_declaration"
	DocInspectionCertificate DocumentType = "inspection_certificate"
	DocInsuranceCertificate  DocumentType = "insurance_certificate"
)

type RFQ struct {
	ID                 string    `json:"id" db:"id"`
	RFQNumber          string    `json:"rfq_number" db:"rfq_number"`
	ImporterID         string    `json:"importer_id" db:"importer_id"`
	ProductName        string    `json:"product_name" db:"product_name"`
	HSNCode            *string   `json:"hsn_code,omitempty" db:"hsn_code"`
	Quantity           float64   `json:"quantity" db:"quantity"`
	Unit               string    `json:"unit" db:"unit"`
	TargetPrice        *float64  `json:"target_price,omitempty" db:"target_price"`
	DestinationCountry string    `json:"destination_country" db:"destination_country"`
	Description        *string   `json:"description,omitempty" db:"description"`
	Status             RFQStatus `json:"status" db:"status"`
	CreatedAt          time.Time `json:"created_at" db:"created_at"`
	UpdatedAt          time.Time `json:"updated_at" db:"updated_at"`
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

// Document — the "current version" pointer for one (order_id, type) pair. FileURL is a
// short-lived signed download URL (Journey 9: "signed sharing"), not a permanent public path —
// generated fresh by the handler on every read, never stored as such.
type Document struct {
	ID          string       `json:"id" db:"id"`
	OrderID     string       `json:"order_id" db:"order_id"`
	Type        DocumentType `json:"type" db:"type"`
	FileURL     string       `json:"file_url" db:"file_url"`
	StorageKey  string       `json:"-" db:"storage_key"`
	Version     int          `json:"version" db:"version"`
	Checksum    string       `json:"checksum" db:"checksum"`
	Signature   string       `json:"signature" db:"signature"`
	GeneratedBy string       `json:"generated_by" db:"generated_by"`
	CreatedAt   time.Time    `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time    `json:"updated_at" db:"updated_at"`
}

// DocumentVersion — Journey 9 "version history": one row per past generation of a document,
// kept even after `documents` is overwritten with the current version.
type DocumentVersion struct {
	ID          string    `json:"id" db:"id"`
	DocumentID  string    `json:"document_id" db:"document_id"`
	Version     int       `json:"version" db:"version"`
	StorageKey  string    `json:"-" db:"storage_key"`
	FileURL     string    `json:"file_url" db:"-"` // populated by the handler, same as Document.FileURL
	Checksum    string    `json:"checksum" db:"checksum"`
	Signature   string    `json:"signature" db:"signature"`
	GeneratedBy string    `json:"generated_by" db:"generated_by"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}
