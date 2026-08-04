package models

import "time"

type UserRole string

const (
	RoleImporter  UserRole = "importer"
	RoleExporter  UserRole = "exporter"
	RoleLogistics UserRole = "logistics"
	RoleAdmin     UserRole = "admin"
)

type KYCStatus string

const (
	KYCPending   KYCStatus = "pending"
	KYCSubmitted KYCStatus = "submitted"
	KYCVerified  KYCStatus = "verified"
	KYCRejected  KYCStatus = "rejected"
)

type User struct {
	ID                    string    `json:"id" db:"id"`
	Role                  UserRole  `json:"role" db:"role"`
	FullName              string    `json:"full_name" db:"full_name"`
	CompanyName           *string   `json:"company_name,omitempty" db:"company_name"`
	Email                 string    `json:"email" db:"email"`
	Phone                 string    `json:"phone" db:"phone"`
	AvatarURL             *string   `json:"avatar_url,omitempty" db:"avatar_url"`
	PasswordHash          string    `json:"-" db:"password_hash"`
	IsActive              bool      `json:"is_active" db:"is_active"`
	IsEmailVerified       bool      `json:"is_email_verified" db:"is_email_verified"`
	IsPhoneVerified       bool      `json:"is_phone_verified" db:"is_phone_verified"`
	RazorpayContactID     *string   `json:"-" db:"razorpay_contact_id"`
	RazorpayFundAccountID *string   `json:"-" db:"razorpay_fund_account_id"`
	ChatPublicKey         *string   `json:"chat_public_key,omitempty" db:"chat_public_key"`
	CreatedAt             time.Time `json:"created_at" db:"created_at"`
	UpdatedAt             time.Time `json:"updated_at" db:"updated_at"`
}

type KYCDetails struct {
	ID                    string     `json:"id" db:"id"`
	UserID                string     `json:"user_id" db:"user_id"`
	Status                KYCStatus  `json:"status" db:"status"`
	PANNumber             *string    `json:"pan_number,omitempty" db:"pan_number"`
	GSTNumber             *string    `json:"gst_number,omitempty" db:"gst_number"`
	IECCode               *string    `json:"iec_code,omitempty" db:"iec_code"`
	BusinessLicense       *string    `json:"business_license,omitempty" db:"business_license"`
	PANDocURL             *string    `json:"pan_doc_url,omitempty" db:"pan_doc_url"`
	GSTDocURL             *string    `json:"gst_doc_url,omitempty" db:"gst_doc_url"`
	IECDocURL             *string    `json:"iec_doc_url,omitempty" db:"iec_doc_url"`
	AddressDocURL         *string    `json:"address_doc_url,omitempty" db:"address_doc_url"`
	BankAccountHolderName *string    `json:"bank_account_holder_name,omitempty" db:"bank_account_holder_name"`
	BankAccountNumber     *string    `json:"bank_account_number,omitempty" db:"bank_account_number"`
	BankIFSC              *string    `json:"bank_ifsc,omitempty" db:"bank_ifsc"`
	RejectionReason       *string    `json:"rejection_reason,omitempty" db:"rejection_reason"`
	VerifiedBy            *string    `json:"verified_by,omitempty" db:"verified_by"`
	VerifiedAt            *time.Time `json:"verified_at,omitempty" db:"verified_at"`
	CreatedAt             time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at" db:"updated_at"`
}
