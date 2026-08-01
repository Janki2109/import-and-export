package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type AdminRepository struct {
	db *pgxpool.Pool
}

func NewAdminRepository(db *pgxpool.Pool) *AdminRepository {
	return &AdminRepository{db: db}
}

func (r *AdminRepository) ListUsers(ctx context.Context, role *string, limit, offset int) ([]models.User, error) {
	query := `SELECT id, role, full_name, company_name, email, phone, password_hash,
		is_active, is_email_verified, is_phone_verified, razorpay_contact_id,
		razorpay_fund_account_id, created_at, updated_at
		FROM users WHERE ($1::text IS NULL OR role = $1::user_role)
		ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, role, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.User
	for rows.Next() {
		var u models.User
		if err := rows.Scan(&u.ID, &u.Role, &u.FullName, &u.CompanyName, &u.Email, &u.Phone, &u.PasswordHash,
			&u.IsActive, &u.IsEmailVerified, &u.IsPhoneVerified, &u.RazorpayContactID, &u.RazorpayFundAccountID,
			&u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, nil
}

func (r *AdminRepository) SetUserActive(ctx context.Context, userID string, active bool) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET is_active = $1 WHERE id = $2`, active, userID)
	return err
}

// ---------------- Rich user view (User Management screen) ----------------

// AdminUserRow adds everything User Management needs beyond the base User: company/country
// (from companies), and GST/IEC/verification (from kyc_details) — all LEFT JOINed since
// a user may not have completed company or KYC onboarding yet.
type AdminUserRow struct {
	models.User
	Country   *string `json:"country,omitempty"`
	GSTNumber *string `json:"gst_number,omitempty"`
	IECCode   *string `json:"iec_code,omitempty"`
	KYCStatus *string `json:"kyc_status,omitempty"`
}

func (r *AdminRepository) ListUsersRich(ctx context.Context, role *string, limit, offset int) ([]AdminUserRow, error) {
	query := `SELECT u.id, u.role, u.full_name, u.company_name, u.email, u.phone, u.password_hash,
		u.is_active, u.is_email_verified, u.is_phone_verified, u.razorpay_contact_id,
		u.razorpay_fund_account_id, u.created_at, u.updated_at,
		c.country, k.gst_number, k.iec_code, k.status::text
		FROM users u
		LEFT JOIN companies c ON c.user_id = u.id
		LEFT JOIN kyc_details k ON k.user_id = u.id
		WHERE ($1::text IS NULL OR u.role = $1::user_role)
		ORDER BY u.created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, role, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminUserRow
	for rows.Next() {
		var row AdminUserRow
		if err := rows.Scan(&row.ID, &row.Role, &row.FullName, &row.CompanyName, &row.Email, &row.Phone, &row.PasswordHash,
			&row.IsActive, &row.IsEmailVerified, &row.IsPhoneVerified, &row.RazorpayContactID, &row.RazorpayFundAccountID,
			&row.CreatedAt, &row.UpdatedAt, &row.Country, &row.GSTNumber, &row.IECCode, &row.KYCStatus); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

// DeleteUser refuses to delete anyone with existing trade activity (orders, RFQs, or
// quotations) — admins should suspend those accounts instead. Only a genuinely unused
// account (e.g. a stale registration) can be hard-deleted.
func (r *AdminRepository) DeleteUser(ctx context.Context, userID string) error {
	var activityCount int
	err := r.db.QueryRow(ctx, `SELECT
		(SELECT COUNT(*) FROM orders WHERE importer_id = $1 OR exporter_id = $1) +
		(SELECT COUNT(*) FROM rfqs WHERE importer_id = $1) +
		(SELECT COUNT(*) FROM quotations WHERE exporter_id = $1)
	`, userID).Scan(&activityCount)
	if err != nil {
		return err
	}
	if activityCount > 0 {
		return fmt.Errorf("cannot delete: this user has existing orders/RFQs/quotations — suspend the account instead")
	}
	_, err = r.db.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID)
	return err
}

func (r *AdminRepository) ListAllOrders(ctx context.Context, status *string, limit, offset int) ([]models.Order, error) {
	query := `SELECT id, order_number, importer_id, exporter_id, product_name, hsn_code,
		quantity, unit, unit_price, currency, total_amount, platform_fee_percent,
		platform_fee_amount, exporter_payout_amount, status, auto_release_days,
		delivery_address, notes, created_at, updated_at
		FROM orders WHERE ($1::text IS NULL OR status = $1::order_status)
		ORDER BY created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, status, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Order
	for rows.Next() {
		var o models.Order
		if err := rows.Scan(&o.ID, &o.OrderNumber, &o.ImporterID, &o.ExporterID, &o.ProductName, &o.HSNCode,
			&o.Quantity, &o.Unit, &o.UnitPrice, &o.Currency, &o.TotalAmount, &o.PlatformFeePercent,
			&o.PlatformFeeAmount, &o.ExporterPayoutAmount, &o.Status, &o.AutoReleaseDays,
			&o.DeliveryAddress, &o.Notes, &o.CreatedAt, &o.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, nil
}

// ---------------- Rich order view (Order Management screen) ----------------

// AdminOrderRow adds importer/exporter/logistics names plus escrow and shipment status —
// everything Order Management needs in one row, already joined server-side.
type AdminOrderRow struct {
	models.Order
	ImporterName   string  `json:"importer_name"`
	ExporterName   string  `json:"exporter_name"`
	LogisticsName  *string `json:"logistics_name,omitempty"`
	EscrowStatus   *string `json:"escrow_status,omitempty"`
	ShipmentStatus *string `json:"shipment_status,omitempty"`
}

func (r *AdminRepository) ListAllOrdersRich(ctx context.Context, status *string, limit, offset int) ([]AdminOrderRow, error) {
	query := `SELECT o.id, o.order_number, o.importer_id, o.exporter_id, o.product_name, o.hsn_code,
		o.quantity, o.unit, o.unit_price, o.currency, o.total_amount, o.platform_fee_percent,
		o.platform_fee_amount, o.exporter_payout_amount, o.status, o.auto_release_days,
		o.delivery_address, o.notes, o.created_at, o.updated_at,
		imp.full_name, exp.full_name, log.full_name, e.status::text, s.status::text
		FROM orders o
		JOIN users imp ON imp.id = o.importer_id
		JOIN users exp ON exp.id = o.exporter_id
		LEFT JOIN shipments s ON s.order_id = o.id
		LEFT JOIN users log ON log.id = s.logistics_id
		LEFT JOIN escrow_payments e ON e.order_id = o.id
		WHERE ($1::text IS NULL OR o.status = $1::order_status)
		ORDER BY o.created_at DESC LIMIT $2 OFFSET $3`
	rows, err := r.db.Query(ctx, query, status, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminOrderRow
	for rows.Next() {
		var row AdminOrderRow
		if err := rows.Scan(&row.ID, &row.OrderNumber, &row.ImporterID, &row.ExporterID, &row.ProductName, &row.HSNCode,
			&row.Quantity, &row.Unit, &row.UnitPrice, &row.Currency, &row.TotalAmount, &row.PlatformFeePercent,
			&row.PlatformFeeAmount, &row.ExporterPayoutAmount, &row.Status, &row.AutoReleaseDays,
			&row.DeliveryAddress, &row.Notes, &row.CreatedAt, &row.UpdatedAt,
			&row.ImporterName, &row.ExporterName, &row.LogisticsName, &row.EscrowStatus, &row.ShipmentStatus); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

// ---------------- Quotation Management ----------------

type AdminQuotationRow struct {
	models.Quotation
	ProductName  string `json:"product_name"`
	ImporterName string `json:"importer_name"`
	ExporterName string `json:"exporter_name"`
}

func (r *AdminRepository) ListAllQuotations(ctx context.Context, limit, offset int) ([]AdminQuotationRow, error) {
	query := `SELECT q.id, q.rfq_id, q.exporter_id, q.unit_price, q.quantity, q.total_amount,
		q.validity_date, q.terms, q.status, q.order_id, q.created_at, q.updated_at,
		r.product_name, imp.full_name, exp.full_name
		FROM quotations q
		JOIN rfqs r ON r.id = q.rfq_id
		JOIN users imp ON imp.id = r.importer_id
		JOIN users exp ON exp.id = q.exporter_id
		ORDER BY q.created_at DESC LIMIT $1 OFFSET $2`
	rows, err := r.db.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminQuotationRow
	for rows.Next() {
		var row AdminQuotationRow
		if err := rows.Scan(&row.ID, &row.RFQID, &row.ExporterID, &row.UnitPrice, &row.Quantity, &row.TotalAmount,
			&row.ValidityDate, &row.Terms, &row.Status, &row.OrderID, &row.CreatedAt, &row.UpdatedAt,
			&row.ProductName, &row.ImporterName, &row.ExporterName); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

// ---------------- Wallet Management (every user's wallet at a glance) ----------------

type AdminWalletRow struct {
	UserID         string  `json:"user_id"`
	FullName       string  `json:"full_name"`
	Role           string  `json:"role"`
	Balance        float64 `json:"balance"`
	PendingRelease float64 `json:"pending_release"`
	TotalReleased  float64 `json:"total_released"`
	TotalWithdrawn float64 `json:"total_withdrawn"`
}

// ListAllWallets computes every user's ledger balance/withdrawn total in one GROUP BY pass
// (avoiding one query per user), then left-joins in escrow pending/released totals — those
// only apply to exporters, so importers/logistics/admins simply get 0 there.
func (r *AdminRepository) ListAllWallets(ctx context.Context) ([]AdminWalletRow, error) {
	query := `SELECT u.id, u.full_name, u.role::text,
		COALESCE(l.balance, 0),
		COALESCE(esc.pending_release, 0),
		COALESCE(esc.total_released, 0),
		COALESCE(l.total_withdrawn, 0)
		FROM users u
		LEFT JOIN (
			SELECT user_id,
				SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) AS balance,
				SUM(amount) FILTER (WHERE entry_type = 'debit' AND description = 'Withdrawal to bank account') AS total_withdrawn
			FROM ledger_entries WHERE user_id IS NOT NULL GROUP BY user_id
		) l ON l.user_id = u.id
		LEFT JOIN (
			SELECT o.exporter_id,
				SUM(e.amount) FILTER (WHERE e.status IN ('held','on_hold')) AS pending_release,
				SUM(e.payout_amount) FILTER (WHERE e.status = 'released') AS total_released
			FROM escrow_payments e JOIN orders o ON o.id = e.order_id GROUP BY o.exporter_id
		) esc ON esc.exporter_id = u.id
		WHERE u.role IN ('importer', 'exporter', 'admin')
		ORDER BY u.role, u.full_name`
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminWalletRow
	for rows.Next() {
		var row AdminWalletRow
		if err := rows.Scan(&row.UserID, &row.FullName, &row.Role, &row.Balance, &row.PendingRelease, &row.TotalReleased, &row.TotalWithdrawn); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

// ---------------- Withdrawal Requests ----------------

// AdminWithdrawalRow — a withdrawal debit from the ledger, with its status derived the same
// way the frontend already does (see wallet_transaction_helpers.dart): a reference_id still
// starting with "MANUAL-PENDING-" means ops hasn't paid it out yet.
type AdminWithdrawalRow struct {
	ID          string    `json:"id"`
	UserID      string    `json:"user_id"`
	UserName    string    `json:"user_name"`
	Role        string    `json:"role"`
	Amount      float64   `json:"amount"`
	ReferenceID *string   `json:"reference_id,omitempty"`
	Status      string    `json:"status"` // pending | paid | rejected
	CreatedAt   time.Time `json:"created_at"`
}

func (r *AdminRepository) ListWithdrawals(ctx context.Context) ([]AdminWithdrawalRow, error) {
	query := `SELECT l.id, l.user_id, u.full_name, u.role::text, l.amount, l.reference_id, l.created_at
		FROM ledger_entries l
		JOIN users u ON u.id = l.user_id
		WHERE l.entry_type = 'debit' AND l.description = 'Withdrawal to bank account'
		ORDER BY l.created_at DESC LIMIT 200`
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminWithdrawalRow
	for rows.Next() {
		var row AdminWithdrawalRow
		if err := rows.Scan(&row.ID, &row.UserID, &row.UserName, &row.Role, &row.Amount, &row.ReferenceID, &row.CreatedAt); err != nil {
			return nil, err
		}
		switch {
		case row.ReferenceID != nil && len(*row.ReferenceID) >= 15 && (*row.ReferenceID)[:15] == "MANUAL-PENDING-":
			row.Status = "pending"
		case row.ReferenceID != nil && len(*row.ReferenceID) >= 8 && (*row.ReferenceID)[:8] == "REJECTED":
			row.Status = "rejected"
		default:
			row.Status = "paid"
		}
		out = append(out, row)
	}
	return out, nil
}

// MarkWithdrawalPaid — admin confirms the bank/UPI transfer went through outside the app.
// Purely updates the audit reference on the existing ledger row; the balance math (already
// debited at request time, per WalletService.Withdraw) is untouched.
func (r *AdminRepository) MarkWithdrawalPaid(ctx context.Context, entryID, adminID string) error {
	ref := fmt.Sprintf("PAID-BY-%s-%d", adminID, time.Now().Unix())
	_, err := r.db.Exec(ctx, `UPDATE ledger_entries SET reference_id = $1 WHERE id = $2 AND entry_type = 'debit' AND description = 'Withdrawal to bank account'`, ref, entryID)
	return err
}

// RejectWithdrawal — reverses the debit by appending a new credit entry for the same amount
// (the ledger is append-only, same pattern every other credit in this app uses — e.g.
// dispute refunds), then marks the original debit's reference so it stops showing as pending.
// This never mutates wallet balance logic itself, only appends an entry through the existing
// ledger mechanism.
func (r *AdminRepository) RejectWithdrawal(ctx context.Context, entryID, adminID, reason string) error {
	var userID string
	var amount float64
	if err := r.db.QueryRow(ctx, `SELECT user_id, amount FROM ledger_entries WHERE id = $1 AND entry_type = 'debit' AND description = 'Withdrawal to bank account'`, entryID).Scan(&userID, &amount); err != nil {
		return err
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	ref := fmt.Sprintf("REJECTED-BY-%s-%d", adminID, time.Now().Unix())
	if _, err := tx.Exec(ctx, `UPDATE ledger_entries SET reference_id = $1 WHERE id = $2`, ref, entryID); err != nil {
		return err
	}
	desc := fmt.Sprintf("Withdrawal Rejected — Refunded (%s)", reason)
	if _, err := tx.Exec(ctx, `INSERT INTO ledger_entries (user_id, entry_type, amount, description, reference_id) VALUES ($1, 'credit', $2, $3, $4)`, userID, amount, desc, ref); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *AdminRepository) GetAnalytics(ctx context.Context) (*models.Analytics, error) {
	a := &models.Analytics{OrdersByStatus: map[string]int{}}

	err := r.db.QueryRow(ctx, `SELECT
		(SELECT COUNT(*) FROM users),
		(SELECT COUNT(*) FROM users WHERE role = 'importer'),
		(SELECT COUNT(*) FROM users WHERE role = 'exporter'),
		(SELECT COUNT(*) FROM users WHERE role = 'logistics'),
		(SELECT COUNT(*) FROM orders),
		(SELECT COALESCE(SUM(total_amount), 0) FROM orders),
		(SELECT COALESCE(SUM(platform_fee_amount), 0) FROM orders WHERE status = 'payment_released'),
		(SELECT COUNT(*) FROM kyc_details WHERE status = 'submitted'),
		(SELECT COUNT(*) FROM disputes WHERE status = 'open')
	`).Scan(&a.TotalUsers, &a.TotalImporters, &a.TotalExporters, &a.TotalLogistics,
		&a.TotalOrders, &a.TotalGMV, &a.TotalPlatformFees, &a.PendingKYCCount, &a.OpenDisputesCount)
	if err != nil {
		return nil, err
	}

	rows, err := r.db.Query(ctx, `SELECT status, COUNT(*) FROM orders GROUP BY status`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var status string
		var count int
		if err := rows.Scan(&status, &count); err != nil {
			return nil, err
		}
		a.OrdersByStatus[status] = count
	}

	return a, nil
}

// ---------------- Dashboard charts ----------------

type MonthPoint struct {
	Month string  `json:"month"`
	Count int     `json:"count"`
	Value float64 `json:"value"`
}

type NamedCount struct {
	Label string `json:"label"`
	Count int    `json:"count"`
}

// ChartAnalytics feeds the admin dashboard's chart section — everything computed with
// simple GROUP BY queries over existing tables, no schema change required.
type ChartAnalytics struct {
	MonthlyOrders       []MonthPoint `json:"monthly_orders"`
	MonthlyRevenue      []MonthPoint `json:"monthly_revenue"`
	CountryTrade        []NamedCount `json:"country_trade"`
	RFQTrend            []MonthPoint `json:"rfq_trend"`
	TopExportCategories []NamedCount `json:"top_export_categories"`
	OpenRFQCount        int          `json:"open_rfq_count"`
	ActiveShipmentCount int          `json:"active_shipment_count"`
	WalletTxnCount      int          `json:"wallet_txn_count"`
}

func (r *AdminRepository) GetChartAnalytics(ctx context.Context) (*ChartAnalytics, error) {
	out := &ChartAnalytics{}

	monthlyRows, err := r.db.Query(ctx, `
		SELECT to_char(date_trunc('month', created_at), 'Mon YYYY') AS m, COUNT(*), COALESCE(SUM(total_amount), 0)
		FROM orders
		WHERE created_at >= now() - interval '6 months'
		GROUP BY date_trunc('month', created_at)
		ORDER BY date_trunc('month', created_at)`)
	if err != nil {
		return nil, err
	}
	for monthlyRows.Next() {
		var p MonthPoint
		if err := monthlyRows.Scan(&p.Month, &p.Count, &p.Value); err != nil {
			monthlyRows.Close()
			return nil, err
		}
		out.MonthlyOrders = append(out.MonthlyOrders, p)
	}
	monthlyRows.Close()

	revenueRows, err := r.db.Query(ctx, `
		SELECT to_char(date_trunc('month', created_at), 'Mon YYYY') AS m, COUNT(*), COALESCE(SUM(platform_fee_amount), 0)
		FROM orders
		WHERE status = 'payment_released' AND created_at >= now() - interval '6 months'
		GROUP BY date_trunc('month', created_at)
		ORDER BY date_trunc('month', created_at)`)
	if err != nil {
		return nil, err
	}
	for revenueRows.Next() {
		var p MonthPoint
		if err := revenueRows.Scan(&p.Month, &p.Count, &p.Value); err != nil {
			revenueRows.Close()
			return nil, err
		}
		out.MonthlyRevenue = append(out.MonthlyRevenue, p)
	}
	revenueRows.Close()

	countryRows, err := r.db.Query(ctx, `
		SELECT destination_country, COUNT(*) FROM rfqs
		GROUP BY destination_country ORDER BY COUNT(*) DESC LIMIT 8`)
	if err != nil {
		return nil, err
	}
	for countryRows.Next() {
		var n NamedCount
		if err := countryRows.Scan(&n.Label, &n.Count); err != nil {
			countryRows.Close()
			return nil, err
		}
		out.CountryTrade = append(out.CountryTrade, n)
	}
	countryRows.Close()

	rfqRows, err := r.db.Query(ctx, `
		SELECT to_char(date_trunc('month', created_at), 'Mon YYYY') AS m, COUNT(*), 0
		FROM rfqs
		WHERE created_at >= now() - interval '6 months'
		GROUP BY date_trunc('month', created_at)
		ORDER BY date_trunc('month', created_at)`)
	if err != nil {
		return nil, err
	}
	for rfqRows.Next() {
		var p MonthPoint
		if err := rfqRows.Scan(&p.Month, &p.Count, &p.Value); err != nil {
			rfqRows.Close()
			return nil, err
		}
		out.RFQTrend = append(out.RFQTrend, p)
	}
	rfqRows.Close()

	categoryRows, err := r.db.Query(ctx, `
		SELECT product_name, COUNT(*) FROM orders
		GROUP BY product_name ORDER BY COUNT(*) DESC LIMIT 5`)
	if err != nil {
		return nil, err
	}
	for categoryRows.Next() {
		var n NamedCount
		if err := categoryRows.Scan(&n.Label, &n.Count); err != nil {
			categoryRows.Close()
			return nil, err
		}
		out.TopExportCategories = append(out.TopExportCategories, n)
	}
	categoryRows.Close()

	if err := r.db.QueryRow(ctx, `SELECT
		(SELECT COUNT(*) FROM rfqs WHERE status = 'open'),
		(SELECT COUNT(*) FROM shipments WHERE status NOT IN ('delivered', 'exception')),
		(SELECT COUNT(*) FROM ledger_entries)
	`).Scan(&out.OpenRFQCount, &out.ActiveShipmentCount, &out.WalletTxnCount); err != nil {
		return nil, err
	}

	return out, nil
}

// ---------------- Admin-wide RFQ / Shipment views ----------------

type AdminRFQRow struct {
	models.RFQ
	ImporterName string `json:"importer_name"`
}

func (r *AdminRepository) ListAllRFQs(ctx context.Context, limit, offset int) ([]AdminRFQRow, error) {
	query := `SELECT r.id, r.rfq_number, r.importer_id, imp.full_name, r.product_name, r.hsn_code,
		r.quantity, r.unit, r.target_price, r.destination_country, r.description, r.status,
		r.created_at, r.updated_at
		FROM rfqs r JOIN users imp ON imp.id = r.importer_id
		ORDER BY r.created_at DESC LIMIT $1 OFFSET $2`
	rows, err := r.db.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminRFQRow
	for rows.Next() {
		var row AdminRFQRow
		if err := rows.Scan(&row.ID, &row.RFQNumber, &row.ImporterID, &row.ImporterName, &row.ProductName,
			&row.HSNCode, &row.Quantity, &row.Unit, &row.TargetPrice, &row.DestinationCountry,
			&row.Description, &row.Status, &row.CreatedAt, &row.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

func (r *AdminRepository) DeleteRFQ(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM rfqs WHERE id = $1`, id)
	return err
}

type AdminShipmentRow struct {
	models.Shipment
	OrderNumber   string  `json:"order_number"`
	ImporterName  string  `json:"importer_name"`
	ExporterName  string  `json:"exporter_name"`
	LogisticsName *string `json:"logistics_name,omitempty"`
}

func (r *AdminRepository) ListAllShipments(ctx context.Context, limit, offset int) ([]AdminShipmentRow, error) {
	query := `SELECT s.id, s.order_id, s.logistics_id, s.tracking_number, s.status,
		s.pickup_address, s.delivery_address, s.carrier_name, s.estimated_delivery,
		s.picked_up_at, s.delivered_at, s.created_at, s.updated_at,
		o.order_number, imp.full_name, exp.full_name, log.full_name
		FROM shipments s
		JOIN orders o ON o.id = s.order_id
		JOIN users imp ON imp.id = o.importer_id
		JOIN users exp ON exp.id = o.exporter_id
		LEFT JOIN users log ON log.id = s.logistics_id
		ORDER BY s.created_at DESC LIMIT $1 OFFSET $2`
	rows, err := r.db.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminShipmentRow
	for rows.Next() {
		var row AdminShipmentRow
		if err := rows.Scan(&row.ID, &row.OrderID, &row.LogisticsID, &row.TrackingNumber, &row.Status,
			&row.PickupAddress, &row.DeliveryAddress, &row.CarrierName, &row.EstimatedDelivery,
			&row.PickedUpAt, &row.DeliveredAt, &row.CreatedAt, &row.UpdatedAt,
			&row.OrderNumber, &row.ImporterName, &row.ExporterName, &row.LogisticsName); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

// ---------------- Logistics Management ----------------

// AdminLogisticsRow — a logistics-role user plus their fleet size/vehicle types and how
// many shipments they've been assigned. No rating field exists anywhere in the schema
// (nothing collects one yet), so it's intentionally omitted rather than fabricated.
type AdminLogisticsRow struct {
	UserID         string    `json:"user_id"`
	FullName       string    `json:"full_name"`
	CompanyName    *string   `json:"company_name,omitempty"`
	Email          string    `json:"email"`
	Phone          string    `json:"phone"`
	Country        *string   `json:"country,omitempty"`
	IsActive       bool      `json:"is_active"`
	FleetCount     int       `json:"fleet_count"`
	VehicleTypes   *string   `json:"vehicle_types,omitempty"`
	OrdersAssigned int       `json:"orders_assigned"`
	CreatedAt      time.Time `json:"created_at"`
}

func (r *AdminRepository) ListLogistics(ctx context.Context) ([]AdminLogisticsRow, error) {
	query := `SELECT u.id, u.full_name, u.company_name, u.email, u.phone, c.country, u.is_active, u.created_at,
		COALESCE(f.fleet_count, 0), f.vehicle_types,
		COALESCE(s.orders_assigned, 0)
		FROM users u
		LEFT JOIN companies c ON c.user_id = u.id
		LEFT JOIN (
			SELECT logistics_id, COUNT(*) AS fleet_count, string_agg(DISTINCT vehicle_type, ', ') AS vehicle_types
			FROM fleet_vehicles GROUP BY logistics_id
		) f ON f.logistics_id = u.id
		LEFT JOIN (
			SELECT logistics_id, COUNT(*) AS orders_assigned
			FROM shipments WHERE logistics_id IS NOT NULL GROUP BY logistics_id
		) s ON s.logistics_id = u.id
		WHERE u.role = 'logistics'
		ORDER BY u.created_at DESC`
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminLogisticsRow
	for rows.Next() {
		var row AdminLogisticsRow
		if err := rows.Scan(&row.UserID, &row.FullName, &row.CompanyName, &row.Email, &row.Phone, &row.Country,
			&row.IsActive, &row.CreatedAt, &row.FleetCount, &row.VehicleTypes, &row.OrdersAssigned); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

// ---------------- Chat Management ----------------

// AdminConversationRow — every conversation on the platform with both participants' names
// and roles, a last-message preview, and message count. Backed by the existing
// conversations/messages tables plus the new is_archived column.
type AdminConversationRow struct {
	ID                 string     `json:"id"`
	UserAID            string     `json:"user_a_id"`
	UserAName          string     `json:"user_a_name"`
	UserARole          string     `json:"user_a_role"`
	UserBID            string     `json:"user_b_id"`
	UserBName          string     `json:"user_b_name"`
	UserBRole          string     `json:"user_b_role"`
	LastMessagePreview *string    `json:"last_message_preview,omitempty"`
	LastMessageAt      *time.Time `json:"last_message_at,omitempty"`
	MessageCount       int        `json:"message_count"`
	IsArchived         bool       `json:"is_archived"`
	CreatedAt          time.Time  `json:"created_at"`
}

func (r *AdminRepository) ListAllConversations(ctx context.Context) ([]AdminConversationRow, error) {
	query := `SELECT c.id, a.id, a.full_name, a.role::text, b.id, b.full_name, b.role::text,
		lm.content, c.last_message_at, COALESCE(mc.count, 0), c.is_archived, c.created_at
		FROM conversations c
		JOIN users a ON a.id = c.participant_one_id
		JOIN users b ON b.id = c.participant_two_id
		LEFT JOIN LATERAL (
			SELECT content FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1
		) lm ON true
		LEFT JOIN (
			SELECT conversation_id, COUNT(*) AS count FROM messages GROUP BY conversation_id
		) mc ON mc.conversation_id = c.id
		ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC`
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminConversationRow
	for rows.Next() {
		var row AdminConversationRow
		if err := rows.Scan(&row.ID, &row.UserAID, &row.UserAName, &row.UserARole, &row.UserBID, &row.UserBName, &row.UserBRole,
			&row.LastMessagePreview, &row.LastMessageAt, &row.MessageCount, &row.IsArchived, &row.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

func (r *AdminRepository) SetConversationArchived(ctx context.Context, id string, archived bool) error {
	_, err := r.db.Exec(ctx, `UPDATE conversations SET is_archived = $1 WHERE id = $2`, archived, id)
	return err
}

// ---------------- Global Search ----------------

type SearchResult struct {
	Category string `json:"category"`
	ID       string `json:"id"`
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"`
}

// GlobalSearch — up to 5 matches per category (Users, Orders, RFQs, Shipments, Wallet
// Transactions), all simple ILIKE lookups over already-indexed columns. Payments are
// represented via Orders (which already carries escrow/payment status).
func (r *AdminRepository) GlobalSearch(ctx context.Context, q string) ([]SearchResult, error) {
	like := "%" + q + "%"
	var out []SearchResult

	userRows, err := r.db.Query(ctx, `SELECT id, full_name, role::text, email FROM users
		WHERE full_name ILIKE $1 OR email ILIKE $1 OR company_name ILIKE $1 LIMIT 5`, like)
	if err != nil {
		return nil, err
	}
	for userRows.Next() {
		var id, name, role, email string
		if err := userRows.Scan(&id, &name, &role, &email); err != nil {
			userRows.Close()
			return nil, err
		}
		out = append(out, SearchResult{Category: "Users", ID: id, Title: name, Subtitle: fmt.Sprintf("%s · %s", role, email)})
	}
	userRows.Close()

	orderRows, err := r.db.Query(ctx, `SELECT id, order_number, product_name, total_amount FROM orders
		WHERE order_number ILIKE $1 OR product_name ILIKE $1 LIMIT 5`, like)
	if err != nil {
		return nil, err
	}
	for orderRows.Next() {
		var id, number, product string
		var amount float64
		if err := orderRows.Scan(&id, &number, &product, &amount); err != nil {
			orderRows.Close()
			return nil, err
		}
		out = append(out, SearchResult{Category: "Orders", ID: id, Title: number, Subtitle: fmt.Sprintf("%s · ₹%.2f", product, amount)})
	}
	orderRows.Close()

	rfqRows, err := r.db.Query(ctx, `SELECT id, rfq_number, product_name, destination_country FROM rfqs
		WHERE rfq_number ILIKE $1 OR product_name ILIKE $1 LIMIT 5`, like)
	if err != nil {
		return nil, err
	}
	for rfqRows.Next() {
		var id, number, product, dest string
		if err := rfqRows.Scan(&id, &number, &product, &dest); err != nil {
			rfqRows.Close()
			return nil, err
		}
		out = append(out, SearchResult{Category: "RFQs", ID: id, Title: number, Subtitle: fmt.Sprintf("%s · %s", product, dest)})
	}
	rfqRows.Close()

	shipRows, err := r.db.Query(ctx, `SELECT s.id, s.tracking_number, o.order_number, s.status::text FROM shipments s
		JOIN orders o ON o.id = s.order_id
		WHERE s.tracking_number ILIKE $1 OR o.order_number ILIKE $1 LIMIT 5`, like)
	if err != nil {
		return nil, err
	}
	for shipRows.Next() {
		var id, tracking, orderNumber, status string
		if err := shipRows.Scan(&id, &tracking, &orderNumber, &status); err != nil {
			shipRows.Close()
			return nil, err
		}
		out = append(out, SearchResult{Category: "Shipments", ID: id, Title: tracking, Subtitle: fmt.Sprintf("%s · %s", orderNumber, status)})
	}
	shipRows.Close()

	walletRows, err := r.db.Query(ctx, `SELECT l.id, u.full_name, l.description, l.amount FROM ledger_entries l
		JOIN users u ON u.id = l.user_id
		WHERE l.description ILIKE $1 OR l.reference_id ILIKE $1 OR u.full_name ILIKE $1 LIMIT 5`, like)
	if err != nil {
		return nil, err
	}
	for walletRows.Next() {
		var id, name, desc string
		var amount float64
		if err := walletRows.Scan(&id, &name, &desc, &amount); err != nil {
			walletRows.Close()
			return nil, err
		}
		out = append(out, SearchResult{Category: "Wallet Transactions", ID: id, Title: fmt.Sprintf("₹%.2f — %s", amount, desc), Subtitle: name})
	}
	walletRows.Close()

	return out, nil
}
