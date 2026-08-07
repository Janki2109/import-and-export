package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

// PaymentTermsRepository — additive module. Never writes to orders/escrow_payments;
// milestone releases credit ledger_entries directly (same pattern EscrowRepository
// already uses), keeping the existing escrow release path fully untouched.
type PaymentTermsRepository struct {
	db *pgxpool.Pool
}

func NewPaymentTermsRepository(db *pgxpool.Pool) *PaymentTermsRepository {
	return &PaymentTermsRepository{db: db}
}

const paymentTermsCols = `id, order_id, payment_model, currency, total_amount, lc_number, lc_bank_name,
	lc_expiry_date, lc_status, open_account_days, status, created_by, created_at, updated_at`

func scanPaymentTerms(row pgx.Row) (*models.PaymentTerms, error) {
	var t models.PaymentTerms
	err := row.Scan(&t.ID, &t.OrderID, &t.PaymentModel, &t.Currency, &t.TotalAmount, &t.LCNumber, &t.LCBankName,
		&t.LCExpiryDate, &t.LCStatus, &t.OpenAccountDays, &t.Status, &t.CreatedBy, &t.CreatedAt, &t.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *PaymentTermsRepository) Create(ctx context.Context, t *models.PaymentTerms) error {
	query := `INSERT INTO payment_terms (order_id, payment_model, currency, total_amount, lc_number, lc_bank_name,
		lc_expiry_date, lc_status, open_account_days, created_by)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING ` + paymentTermsCols
	row := r.db.QueryRow(ctx, query, t.OrderID, t.PaymentModel, t.Currency, t.TotalAmount, t.LCNumber, t.LCBankName,
		t.LCExpiryDate, t.LCStatus, t.OpenAccountDays, t.CreatedBy)
	res, err := scanPaymentTerms(row)
	if err != nil {
		return err
	}
	*t = *res
	return nil
}

func (r *PaymentTermsRepository) GetByOrderID(ctx context.Context, orderID string) (*models.PaymentTerms, error) {
	row := r.db.QueryRow(ctx, `SELECT `+paymentTermsCols+` FROM payment_terms WHERE order_id = $1`, orderID)
	return scanPaymentTerms(row)
}

func (r *PaymentTermsRepository) GetByID(ctx context.Context, id string) (*models.PaymentTerms, error) {
	row := r.db.QueryRow(ctx, `SELECT `+paymentTermsCols+` FROM payment_terms WHERE id = $1`, id)
	return scanPaymentTerms(row)
}

func (r *PaymentTermsRepository) UpdateLC(ctx context.Context, id string, number, bank *string, expiry *string, status *models.LCStatus) error {
	_, err := r.db.Exec(ctx, `UPDATE payment_terms SET lc_number = COALESCE($1, lc_number), lc_bank_name = COALESCE($2, lc_bank_name),
		lc_expiry_date = COALESCE($3::date, lc_expiry_date), lc_status = COALESCE($4, lc_status), updated_at = now() WHERE id = $5`,
		number, bank, expiry, status, id)
	return err
}

func (r *PaymentTermsRepository) MarkCompleted(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `UPDATE payment_terms SET status = 'completed', updated_at = now() WHERE id = $1`, id)
	return err
}

const milestoneCols = `id, payment_term_id, release_order, title, percentage, amount, status, trigger_event,
	proof_required, proof_url, proof_uploaded_at, uploaded_by, paid_at, reviewed_by, reviewed_at, remarks,
	released_at, created_at, updated_at`

func scanMilestone(row pgx.Row) (*models.PaymentMilestone, error) {
	var m models.PaymentMilestone
	err := row.Scan(&m.ID, &m.PaymentTermID, &m.ReleaseOrder, &m.Title, &m.Percentage, &m.Amount, &m.Status, &m.TriggerEvent,
		&m.ProofRequired, &m.ProofURL, &m.ProofUploadedAt, &m.UploadedBy, &m.PaidAt, &m.ReviewedBy, &m.ReviewedAt, &m.Remarks,
		&m.ReleasedAt, &m.CreatedAt, &m.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

func (r *PaymentTermsRepository) CreateMilestone(ctx context.Context, m *models.PaymentMilestone) error {
	query := `INSERT INTO payment_milestones (payment_term_id, release_order, title, percentage, amount, trigger_event, proof_required)
		VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING ` + milestoneCols
	row := r.db.QueryRow(ctx, query, m.PaymentTermID, m.ReleaseOrder, m.Title, m.Percentage, m.Amount, m.TriggerEvent, m.ProofRequired)
	res, err := scanMilestone(row)
	if err != nil {
		return err
	}
	*m = *res
	return nil
}

func (r *PaymentTermsRepository) ListMilestones(ctx context.Context, paymentTermID string) ([]models.PaymentMilestone, error) {
	rows, err := r.db.Query(ctx, `SELECT `+milestoneCols+` FROM payment_milestones WHERE payment_term_id = $1 ORDER BY release_order`, paymentTermID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.PaymentMilestone
	for rows.Next() {
		m, err := scanMilestone(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *m)
	}
	return out, rows.Err()
}

func (r *PaymentTermsRepository) GetMilestone(ctx context.Context, id string) (*models.PaymentMilestone, error) {
	row := r.db.QueryRow(ctx, `SELECT `+milestoneCols+` FROM payment_milestones WHERE id = $1`, id)
	return scanMilestone(row)
}

// MarkPaid — importer self-declares payment for this milestone (mirrors the existing
// self-declared ConfirmPaymentDone flow, no gateway integration).
func (r *PaymentTermsRepository) MarkPaid(ctx context.Context, id string) error {
	cmd, err := r.db.Exec(ctx, `UPDATE payment_milestones SET status = 'paid', paid_at = now(), updated_at = now()
		WHERE id = $1 AND status = 'pending'`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("milestone is not pending")
	}
	return nil
}

func (r *PaymentTermsRepository) UploadProof(ctx context.Context, id, proofURL, uploadedBy string) error {
	cmd, err := r.db.Exec(ctx, `UPDATE payment_milestones SET proof_url = $1, proof_uploaded_at = now(), uploaded_by = $2,
		status = 'waiting_approval', updated_at = now() WHERE id = $3 AND status IN ('paid','rejected')`, proofURL, uploadedBy, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("milestone must be paid before proof can be uploaded")
	}
	return nil
}

// MarkReadyForReview — used when a milestone doesn't require proof; moves paid -> waiting_approval directly.
func (r *PaymentTermsRepository) MarkReadyForReview(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `UPDATE payment_milestones SET status = 'waiting_approval', updated_at = now()
		WHERE id = $1 AND status = 'paid' AND proof_required = false`, id)
	return err
}

func (r *PaymentTermsRepository) Approve(ctx context.Context, id, adminID string, remarks *string) error {
	cmd, err := r.db.Exec(ctx, `UPDATE payment_milestones SET status = 'approved', reviewed_by = $1, reviewed_at = now(),
		remarks = COALESCE($2, remarks), updated_at = now() WHERE id = $3 AND status = 'waiting_approval'`, adminID, remarks, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("milestone is not waiting for approval")
	}
	return nil
}

func (r *PaymentTermsRepository) Reject(ctx context.Context, id, adminID string, remarks *string) error {
	cmd, err := r.db.Exec(ctx, `UPDATE payment_milestones SET status = 'rejected', reviewed_by = $1, reviewed_at = now(),
		remarks = COALESCE($2, remarks), updated_at = now() WHERE id = $3 AND status = 'waiting_approval'`, adminID, remarks, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("milestone is not waiting for approval")
	}
	return nil
}

func (r *PaymentTermsRepository) Hold(ctx context.Context, id, adminID string, remarks *string) error {
	cmd, err := r.db.Exec(ctx, `UPDATE payment_milestones SET status = 'on_hold', reviewed_by = $1, reviewed_at = now(),
		remarks = COALESCE($2, remarks), updated_at = now() WHERE id = $3 AND status IN ('waiting_approval','approved')`, adminID, remarks, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("milestone cannot be held from its current state")
	}
	return nil
}

func (r *PaymentTermsRepository) Unhold(ctx context.Context, id string) error {
	cmd, err := r.db.Exec(ctx, `UPDATE payment_milestones SET status = 'waiting_approval', updated_at = now()
		WHERE id = $1 AND status = 'on_hold'`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return fmt.Errorf("milestone is not on hold")
	}
	return nil
}

// Release — the money-moving step. Only from 'approved'. Credits the exporter via a new
// ledger_entries row (existing generic table, same shape EscrowRepository.MarkReleased already
// inserts) — escrow_payments and orders rows are never touched.
//
// BUG FIX (H-06): previously credited the exporter the FULL milestone amount with no platform
// fee split at all — unlike the single-payment escrow path (EscrowRepository.MarkReleased),
// which always nets off PlatformFeePercent, milestone-based orders earned the platform ZERO
// commission. payoutAmount/feeAmount are now computed by the caller (same formula CreateOrder
// already uses) and both a platform-fee ledger credit and the exporter payout are written here.
func (r *PaymentTermsRepository) Release(ctx context.Context, milestoneID, orderID, exporterID, adminID string, payoutAmount, feeAmount float64) (*models.PaymentMilestone, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	row := tx.QueryRow(ctx, `UPDATE payment_milestones SET status = 'released', released_at = now(), reviewed_by = COALESCE(reviewed_by, $1),
		updated_at = now() WHERE id = $2 AND status = 'approved' RETURNING `+milestoneCols, adminID, milestoneID)
	m, err := scanMilestone(row)
	if err != nil {
		return nil, fmt.Errorf("milestone is not approved: %w", err)
	}

	_, err = tx.Exec(ctx, `INSERT INTO ledger_entries (order_id, user_id, entry_type, amount, description, reference_id)
		VALUES
			($1, $2, 'credit', $3, $4, $5),
			($1, NULL, 'credit', $6, 'Platform fee earned (milestone release)', $5)`,
		orderID, exporterID, payoutAmount, fmt.Sprintf("Milestone released: %s", m.Title), m.ID, feeAmount)
	if err != nil {
		return nil, fmt.Errorf("ledger entry: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return m, nil
}

// ---- Admin ----

type AdminPaymentRow struct {
	models.PaymentTerms
	OrderNumber    string
	ImporterName   string
	ExporterName   string
	ProductName    string
	MilestoneCount int
	ReleasedCount  int
}

type AdminPaymentFilters struct {
	PaymentModel string
	Search       string
}

func (r *PaymentTermsRepository) AdminList(ctx context.Context, f AdminPaymentFilters) ([]AdminPaymentRow, error) {
	// BUG FIX (H-23): imp.company_name/exp.company_name are nullable (optional at registration)
	// and were scanned into non-pointer string fields — any order whose importer or exporter
	// registered without a company name made this scan fail outright, and GET
	// /admin/payment-terms returned 500 for the WHOLE list on that one row. Sibling admin
	// queries deliberately use full_name (NOT NULL) for exactly this reason; here the columns
	// are genuinely meant to show company name, so COALESCE to full_name as a fallback instead.
	query := `SELECT ` + paymentTermsColsAliased() + `,
		o.order_number, COALESCE(imp.company_name, imp.full_name), COALESCE(exp.company_name, exp.full_name), o.product_name,
		(SELECT COUNT(*) FROM payment_milestones WHERE payment_term_id = pt.id),
		(SELECT COUNT(*) FROM payment_milestones WHERE payment_term_id = pt.id AND status = 'released')
		FROM payment_terms pt
		JOIN orders o ON o.id = pt.order_id
		JOIN users imp ON imp.id = o.importer_id
		JOIN users exp ON exp.id = o.exporter_id
		WHERE 1=1`
	args := []any{}
	i := 1
	if f.PaymentModel != "" {
		query += fmt.Sprintf(" AND pt.payment_model = $%d", i)
		args = append(args, f.PaymentModel)
		i++
	}
	if f.Search != "" {
		query += fmt.Sprintf(` AND (o.order_number ILIKE $%d OR imp.company_name ILIKE $%d OR exp.company_name ILIKE $%d OR o.product_name ILIKE $%d)`, i, i, i, i)
		args = append(args, "%"+f.Search+"%")
		i++
	}
	query += " ORDER BY pt.created_at DESC"

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AdminPaymentRow
	for rows.Next() {
		var row AdminPaymentRow
		if err := rows.Scan(&row.ID, &row.OrderID, &row.PaymentModel, &row.Currency, &row.TotalAmount, &row.LCNumber, &row.LCBankName,
			&row.LCExpiryDate, &row.LCStatus, &row.OpenAccountDays, &row.Status, &row.CreatedBy, &row.CreatedAt, &row.UpdatedAt,
			&row.OrderNumber, &row.ImporterName, &row.ExporterName, &row.ProductName, &row.MilestoneCount, &row.ReleasedCount); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// BUG FIX (C10): previously only the FIRST column got the "pt." prefix (the caller prepended it
// via string concat: `SELECT pt.` + this string), so the rest — order_id, status, created_by,
// created_at, updated_at, etc. — were unqualified. AdminList joins orders and users (twice, as
// imp/exp), both of which also have created_at/updated_at columns, so those unqualified refs
// raised "column reference is ambiguous" and broke the admin Payment Terms screen entirely. Every
// column is now explicitly qualified with pt. here instead.
func paymentTermsColsAliased() string {
	return "pt.id, pt.order_id, pt.payment_model, pt.currency, pt.total_amount, pt.lc_number, pt.lc_bank_name, pt.lc_expiry_date, pt.lc_status, pt.open_account_days, pt.status, pt.created_by, pt.created_at, pt.updated_at"
}

type AdminPaymentSummary struct {
	TotalEscrow        float64
	PendingReleases    int
	Released           float64
	UpcomingMilestones int
	DelayedMilestones  int
}

func (r *PaymentTermsRepository) AdminSummary(ctx context.Context) (*AdminPaymentSummary, error) {
	var s AdminPaymentSummary
	err := r.db.QueryRow(ctx, `SELECT
		COALESCE(SUM(amount) FILTER (WHERE status IN ('paid','waiting_approval','approved')), 0),
		COUNT(*) FILTER (WHERE status = 'waiting_approval'),
		COALESCE(SUM(amount) FILTER (WHERE status = 'released'), 0),
		COUNT(*) FILTER (WHERE status = 'pending'),
		COUNT(*) FILTER (WHERE status = 'on_hold')
		FROM payment_milestones`).Scan(&s.TotalEscrow, &s.PendingReleases, &s.Released, &s.UpcomingMilestones, &s.DelayedMilestones)
	if err != nil {
		return nil, err
	}
	return &s, nil
}
