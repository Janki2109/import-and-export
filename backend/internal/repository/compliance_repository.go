package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type ComplianceRepository struct {
	db *pgxpool.Pool
}

func NewComplianceRepository(db *pgxpool.Pool) *ComplianceRepository {
	return &ComplianceRepository{db: db}
}

// ---------------- Rule engine ----------------

// MatchRules — the entire rule engine. Any of origin/destination/hsCode/shippingMode being
// nil (unknown) still matches rules whose own column is NULL (wildcard); a non-nil rule
// column only matches an equal, non-nil input. This means new trade lanes are supported by
// inserting rows into compliance_rules alone — nothing here is country/product-specific.
func (r *ComplianceRepository) MatchRules(ctx context.Context, origin, destination, hsCode, shippingMode *string) ([]models.ComplianceRule, error) {
	query := `SELECT id, origin_country, destination_country, hs_code, shipping_mode,
		document_name, responsible_role, mandatory, display_order, description, created_at
		FROM compliance_rules
		WHERE (origin_country IS NULL OR origin_country = $1)
		  AND (destination_country IS NULL OR destination_country = $2)
		  AND (hs_code IS NULL OR hs_code = $3)
		  AND (shipping_mode IS NULL OR $4::text IS NULL OR shipping_mode = $4)
		ORDER BY display_order ASC, document_name ASC`
	rows, err := r.db.Query(ctx, query, origin, destination, hsCode, shippingMode)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.ComplianceRule
	for rows.Next() {
		var rule models.ComplianceRule
		if err := rows.Scan(&rule.ID, &rule.OriginCountry, &rule.DestinationCountry, &rule.HSCode, &rule.ShippingMode,
			&rule.DocumentName, &rule.ResponsibleRole, &rule.Mandatory, &rule.DisplayOrder, &rule.Description, &rule.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, rule)
	}
	return out, nil
}

func (r *ComplianceRepository) ListRules(ctx context.Context) ([]models.ComplianceRule, error) {
	rows, err := r.db.Query(ctx, `SELECT id, origin_country, destination_country, hs_code, shipping_mode,
		document_name, responsible_role, mandatory, display_order, description, created_at
		FROM compliance_rules ORDER BY created_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.ComplianceRule
	for rows.Next() {
		var rule models.ComplianceRule
		if err := rows.Scan(&rule.ID, &rule.OriginCountry, &rule.DestinationCountry, &rule.HSCode, &rule.ShippingMode,
			&rule.DocumentName, &rule.ResponsibleRole, &rule.Mandatory, &rule.DisplayOrder, &rule.Description, &rule.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, rule)
	}
	return out, nil
}

func (r *ComplianceRepository) CreateRule(ctx context.Context, rule *models.ComplianceRule) error {
	query := `INSERT INTO compliance_rules (origin_country, destination_country, hs_code, shipping_mode,
		document_name, responsible_role, mandatory, display_order, description)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, rule.OriginCountry, rule.DestinationCountry, rule.HSCode, rule.ShippingMode,
		rule.DocumentName, rule.ResponsibleRole, rule.Mandatory, rule.DisplayOrder, rule.Description).
		Scan(&rule.ID, &rule.CreatedAt)
}

func (r *ComplianceRepository) DeleteRule(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM compliance_rules WHERE id = $1`, id)
	return err
}

// ---------------- Order checklist ----------------

// GenerateChecklist copies every matching rule into order_compliance for this order.
// ON CONFLICT DO NOTHING (the (order_id, document_name) unique constraint) makes this safe
// to call more than once for the same order without creating duplicates.
func (r *ComplianceRepository) GenerateChecklist(ctx context.Context, orderID string, rules []models.ComplianceRule) error {
	if len(rules) == 0 {
		return nil
	}
	for _, rule := range rules {
		_, err := r.db.Exec(ctx, `INSERT INTO order_compliance
			(order_id, rule_id, document_name, responsible_role, mandatory, display_order, description, status)
			VALUES ($1,$2,$3,$4,$5,$6,$7,'pending')
			ON CONFLICT (order_id, document_name) DO NOTHING`,
			orderID, rule.ID, rule.DocumentName, rule.ResponsibleRole, rule.Mandatory, rule.DisplayOrder, rule.Description)
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *ComplianceRepository) ListForOrder(ctx context.Context, orderID string) ([]models.OrderCompliance, error) {
	rows, err := r.db.Query(ctx, `SELECT id, order_id, rule_id, document_name, responsible_role, mandatory, display_order,
		description, status, uploaded_file, remarks, verified_by_admin, uploaded_at, verified_at, created_at, updated_at
		FROM order_compliance WHERE order_id = $1 ORDER BY display_order ASC, document_name ASC`, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanOrderCompliance(rows)
}

func (r *ComplianceRepository) GetByID(ctx context.Context, id string) (*models.OrderCompliance, error) {
	row := r.db.QueryRow(ctx, `SELECT id, order_id, rule_id, document_name, responsible_role, mandatory, display_order,
		description, status, uploaded_file, remarks, verified_by_admin, uploaded_at, verified_at, created_at, updated_at
		FROM order_compliance WHERE id = $1`, id)
	var c models.OrderCompliance
	if err := row.Scan(&c.ID, &c.OrderID, &c.RuleID, &c.DocumentName, &c.ResponsibleRole, &c.Mandatory, &c.DisplayOrder,
		&c.Description, &c.Status, &c.UploadedFile, &c.Remarks, &c.VerifiedByAdmin, &c.UploadedAt, &c.VerifiedAt,
		&c.CreatedAt, &c.UpdatedAt); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}

func (r *ComplianceRepository) UploadDocument(ctx context.Context, id, fileURL, uploaderID string, remarks *string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `UPDATE order_compliance SET status = 'uploaded', uploaded_file = $1, remarks = $2,
		uploaded_at = now(), updated_at = now() WHERE id = $3`, fileURL, remarks, id); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO compliance_document_history (order_compliance_id, file_url, uploaded_by, remarks)
		VALUES ($1,$2,$3,$4)`, id, fileURL, uploaderID, remarks); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *ComplianceRepository) VerifyDocument(ctx context.Context, id, adminID string) error {
	_, err := r.db.Exec(ctx, `UPDATE order_compliance SET status = 'verified', verified_by_admin = $1,
		verified_at = now(), updated_at = now() WHERE id = $2`, adminID, id)
	return err
}

func (r *ComplianceRepository) RejectDocument(ctx context.Context, id, adminID, remarks string) error {
	_, err := r.db.Exec(ctx, `UPDATE order_compliance SET status = 'rejected', verified_by_admin = $1,
		verified_at = now(), remarks = $2, updated_at = now() WHERE id = $3`, adminID, remarks, id)
	return err
}

func (r *ComplianceRepository) ListHistory(ctx context.Context, orderComplianceID string) ([]models.ComplianceDocumentHistory, error) {
	rows, err := r.db.Query(ctx, `SELECT id, order_compliance_id, file_url, uploaded_by, remarks, created_at
		FROM compliance_document_history WHERE order_compliance_id = $1 ORDER BY created_at DESC`, orderComplianceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.ComplianceDocumentHistory
	for rows.Next() {
		var h models.ComplianceDocumentHistory
		if err := rows.Scan(&h.ID, &h.OrderComplianceID, &h.FileURL, &h.UploadedBy, &h.Remarks, &h.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, nil
}

// ---------------- Admin Compliance Center ----------------

// AdminComplianceRow — one checklist item plus enough order/party context for the admin
// list + filters (country, order, exporter, importer, logistics, status, search).
type AdminComplianceRow struct {
	models.OrderCompliance
	OrderNumber   string  `json:"order_number"`
	ImporterName  string  `json:"importer_name"`
	ExporterName  string  `json:"exporter_name"`
	LogisticsName *string `json:"logistics_name,omitempty"`
	OriginCountry *string `json:"origin_country,omitempty"`
	DestCountry   *string `json:"destination_country,omitempty"`
}

type AdminComplianceFilters struct {
	Status  *string
	OrderID *string
	Country *string
	Search  *string
}

func (r *ComplianceRepository) AdminList(ctx context.Context, f AdminComplianceFilters) ([]AdminComplianceRow, error) {
	query := `SELECT oc.id, oc.order_id, oc.rule_id, oc.document_name, oc.responsible_role, oc.mandatory, oc.display_order,
		oc.description, oc.status, oc.uploaded_file, oc.remarks, oc.verified_by_admin, oc.uploaded_at, oc.verified_at,
		oc.created_at, oc.updated_at,
		o.order_number, imp.full_name, exp.full_name, log.full_name, expc.country, impc.country
		FROM order_compliance oc
		JOIN orders o ON o.id = oc.order_id
		JOIN users imp ON imp.id = o.importer_id
		JOIN users exp ON exp.id = o.exporter_id
		LEFT JOIN shipments s ON s.order_id = o.id
		LEFT JOIN users log ON log.id = s.logistics_id
		LEFT JOIN companies expc ON expc.user_id = o.exporter_id
		LEFT JOIN companies impc ON impc.user_id = o.importer_id
		WHERE ($1::text IS NULL OR oc.status::text = $1)
		  AND ($2::uuid IS NULL OR oc.order_id = $2)
		  AND ($3::text IS NULL OR expc.country = $3 OR impc.country = $3)
		  AND ($4::text IS NULL OR oc.document_name ILIKE '%' || $4 || '%' OR o.order_number ILIKE '%' || $4 || '%'
		       OR imp.full_name ILIKE '%' || $4 || '%' OR exp.full_name ILIKE '%' || $4 || '%')
		ORDER BY oc.created_at DESC LIMIT 300`
	rows, err := r.db.Query(ctx, query, f.Status, f.OrderID, f.Country, f.Search)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminComplianceRow
	for rows.Next() {
		var row AdminComplianceRow
		if err := rows.Scan(&row.ID, &row.OrderID, &row.RuleID, &row.DocumentName, &row.ResponsibleRole, &row.Mandatory, &row.DisplayOrder,
			&row.Description, &row.Status, &row.UploadedFile, &row.Remarks, &row.VerifiedByAdmin, &row.UploadedAt, &row.VerifiedAt,
			&row.CreatedAt, &row.UpdatedAt,
			&row.OrderNumber, &row.ImporterName, &row.ExporterName, &row.LogisticsName, &row.OriginCountry, &row.DestCountry); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}

type ComplianceSummary struct {
	PendingVerification int `json:"pending_verification"`
	Verified            int `json:"verified"`
	Rejected            int `json:"rejected"`
	BlockedShipments    int `json:"blocked_shipments"`
}

func (r *ComplianceRepository) Summary(ctx context.Context) (*ComplianceSummary, error) {
	s := &ComplianceSummary{}
	err := r.db.QueryRow(ctx, `SELECT
		(SELECT COUNT(*) FROM order_compliance WHERE status = 'uploaded'),
		(SELECT COUNT(*) FROM order_compliance WHERE status = 'verified'),
		(SELECT COUNT(*) FROM order_compliance WHERE status = 'rejected'),
		(SELECT COUNT(DISTINCT order_id) FROM order_compliance WHERE mandatory = true AND status != 'verified')
	`).Scan(&s.PendingVerification, &s.Verified, &s.Rejected, &s.BlockedShipments)
	if err != nil {
		return nil, err
	}
	return s, nil
}

// IsShipmentBlocked — true if this order has any mandatory checklist item not yet verified.
// Informational only (see ComplianceService docs) — not enforced on the shipment-status
// endpoints themselves, since those belong to the existing logistics workflow.
func (r *ComplianceRepository) IsShipmentBlocked(ctx context.Context, orderID string) (bool, []string, error) {
	rows, err := r.db.Query(ctx, `SELECT document_name FROM order_compliance
		WHERE order_id = $1 AND mandatory = true AND status != 'verified'`, orderID)
	if err != nil {
		return false, nil, err
	}
	defer rows.Close()

	var missing []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return false, nil, err
		}
		missing = append(missing, name)
	}
	return len(missing) > 0, missing, nil
}

func scanOrderCompliance(rows pgx.Rows) ([]models.OrderCompliance, error) {
	var out []models.OrderCompliance
	for rows.Next() {
		var c models.OrderCompliance
		if err := rows.Scan(&c.ID, &c.OrderID, &c.RuleID, &c.DocumentName, &c.ResponsibleRole, &c.Mandatory, &c.DisplayOrder,
			&c.Description, &c.Status, &c.UploadedFile, &c.Remarks, &c.VerifiedByAdmin, &c.UploadedAt, &c.VerifiedAt,
			&c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, nil
}
