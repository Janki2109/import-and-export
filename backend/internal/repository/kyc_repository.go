package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type KYCRepository struct {
	db *pgxpool.Pool
}

func NewKYCRepository(db *pgxpool.Pool) *KYCRepository {
	return &KYCRepository{db: db}
}

// Upsert — user submits/resubmits KYC docs.
func (r *KYCRepository) Upsert(ctx context.Context, k *models.KYCDetails) error {
	query := `
		INSERT INTO kyc_details (user_id, status, pan_number, gst_number, iec_code,
			business_license, pan_doc_url, gst_doc_url, iec_doc_url, address_doc_url,
			bank_account_holder_name, bank_account_number, bank_ifsc)
		VALUES ($1,'submitted',$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
		ON CONFLICT (user_id) DO UPDATE SET
			status = 'submitted',
			pan_number = EXCLUDED.pan_number,
			gst_number = EXCLUDED.gst_number,
			iec_code = EXCLUDED.iec_code,
			business_license = EXCLUDED.business_license,
			pan_doc_url = EXCLUDED.pan_doc_url,
			gst_doc_url = EXCLUDED.gst_doc_url,
			iec_doc_url = EXCLUDED.iec_doc_url,
			address_doc_url = EXCLUDED.address_doc_url,
			bank_account_holder_name = EXCLUDED.bank_account_holder_name,
			bank_account_number = EXCLUDED.bank_account_number,
			bank_ifsc = EXCLUDED.bank_ifsc,
			rejection_reason = NULL
		RETURNING id, created_at, updated_at`

	return r.db.QueryRow(ctx, query, k.UserID, k.PANNumber, k.GSTNumber, k.IECCode,
		k.BusinessLicense, k.PANDocURL, k.GSTDocURL, k.IECDocURL, k.AddressDocURL,
		k.BankAccountHolderName, k.BankAccountNumber, k.BankIFSC,
	).Scan(&k.ID, &k.CreatedAt, &k.UpdatedAt)
}

func (r *KYCRepository) GetByUserID(ctx context.Context, userID string) (*models.KYCDetails, error) {
	query := `SELECT id, user_id, status, pan_number, gst_number, iec_code, business_license,
		pan_doc_url, gst_doc_url, iec_doc_url, address_doc_url,
		bank_account_holder_name, bank_account_number, bank_ifsc, rejection_reason,
		verified_by, verified_at, created_at, updated_at
		FROM kyc_details WHERE user_id = $1`

	var k models.KYCDetails
	err := r.db.QueryRow(ctx, query, userID).Scan(
		&k.ID, &k.UserID, &k.Status, &k.PANNumber, &k.GSTNumber, &k.IECCode, &k.BusinessLicense,
		&k.PANDocURL, &k.GSTDocURL, &k.IECDocURL, &k.AddressDocURL,
		&k.BankAccountHolderName, &k.BankAccountNumber, &k.BankIFSC, &k.RejectionReason,
		&k.VerifiedBy, &k.VerifiedAt, &k.CreatedAt, &k.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &k, nil
}

func (r *KYCRepository) ListPending(ctx context.Context, limit, offset int) ([]models.KYCDetails, error) {
	query := `SELECT id, user_id, status, pan_number, gst_number, iec_code, business_license,
		pan_doc_url, gst_doc_url, iec_doc_url, address_doc_url,
		bank_account_holder_name, bank_account_number, bank_ifsc, rejection_reason,
		verified_by, verified_at, created_at, updated_at
		FROM kyc_details WHERE status = 'submitted' ORDER BY created_at ASC LIMIT $1 OFFSET $2`

	rows, err := r.db.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []models.KYCDetails
	for rows.Next() {
		var k models.KYCDetails
		if err := rows.Scan(
			&k.ID, &k.UserID, &k.Status, &k.PANNumber, &k.GSTNumber, &k.IECCode, &k.BusinessLicense,
			&k.PANDocURL, &k.GSTDocURL, &k.IECDocURL, &k.AddressDocURL,
			&k.BankAccountHolderName, &k.BankAccountNumber, &k.BankIFSC, &k.RejectionReason,
			&k.VerifiedBy, &k.VerifiedAt, &k.CreatedAt, &k.UpdatedAt,
		); err != nil {
			return nil, err
		}
		list = append(list, k)
	}
	return list, nil
}

// Approve/Reject by admin. If approved, also stores the Razorpay contact_id + fund_account_id
// (created by the service layer after calling Razorpay) so payouts can happen later.
func (r *KYCRepository) UpdateStatus(ctx context.Context, userID, status string, adminID string, rejectionReason *string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE kyc_details
		SET status = $1, rejection_reason = $2, verified_by = $3, verified_at = now()
		WHERE user_id = $4`,
		status, rejectionReason, adminID, userID)
	return err
}
