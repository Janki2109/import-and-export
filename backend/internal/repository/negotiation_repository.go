package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type NegotiationRepository struct {
	db *pgxpool.Pool
}

func NewNegotiationRepository(db *pgxpool.Pool) *NegotiationRepository {
	return &NegotiationRepository{db: db}
}

// ---------------- Negotiations ----------------

func (r *NegotiationRepository) Create(ctx context.Context, n *models.Negotiation) error {
	query := `INSERT INTO negotiations (rfq_id, quotation_id, importer_id, exporter_id, status, current_round)
		VALUES ($1,$2,$3,$4,$5,$6) RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query, n.RFQID, n.QuotationID, n.ImporterID, n.ExporterID, n.Status, n.CurrentRound).
		Scan(&n.ID, &n.CreatedAt, &n.UpdatedAt)
}

func (r *NegotiationRepository) GetByID(ctx context.Context, id string) (*models.Negotiation, error) {
	return r.scanOneNegotiation(ctx, `SELECT id, rfq_id, quotation_id, importer_id, exporter_id, status, current_round, created_at, updated_at
		FROM negotiations WHERE id = $1`, id)
}

func (r *NegotiationRepository) GetByQuotationID(ctx context.Context, quotationID string) (*models.Negotiation, error) {
	return r.scanOneNegotiation(ctx, `SELECT id, rfq_id, quotation_id, importer_id, exporter_id, status, current_round, created_at, updated_at
		FROM negotiations WHERE quotation_id = $1`, quotationID)
}

func (r *NegotiationRepository) scanOneNegotiation(ctx context.Context, query string, arg string) (*models.Negotiation, error) {
	var n models.Negotiation
	err := r.db.QueryRow(ctx, query, arg).Scan(&n.ID, &n.RFQID, &n.QuotationID, &n.ImporterID, &n.ExporterID,
		&n.Status, &n.CurrentRound, &n.CreatedAt, &n.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &n, nil
}

func (r *NegotiationRepository) UpdateStatus(ctx context.Context, id string, status models.NegotiationStatus) error {
	_, err := r.db.Exec(ctx, `UPDATE negotiations SET status = $1, updated_at = now() WHERE id = $2`, status, id)
	return err
}

func (r *NegotiationRepository) IncrementRound(ctx context.Context, id string) (int, error) {
	var round int
	err := r.db.QueryRow(ctx, `UPDATE negotiations SET current_round = current_round + 1, updated_at = now()
		WHERE id = $1 RETURNING current_round`, id).Scan(&round)
	return round, err
}

func (r *NegotiationRepository) ListMine(ctx context.Context, userID string, role models.UserRole) ([]models.Negotiation, error) {
	col := "importer_id"
	if role == models.RoleExporter {
		col = "exporter_id"
	}
	query := fmt.Sprintf(`SELECT id, rfq_id, quotation_id, importer_id, exporter_id, status, current_round, created_at, updated_at
		FROM negotiations WHERE %s = $1 ORDER BY updated_at DESC`, col)
	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Negotiation
	for rows.Next() {
		var n models.Negotiation
		if err := rows.Scan(&n.ID, &n.RFQID, &n.QuotationID, &n.ImporterID, &n.ExporterID, &n.Status, &n.CurrentRound, &n.CreatedAt, &n.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, nil
}

// ---------------- Offers (the structured timeline) ----------------

func (r *NegotiationRepository) CreateOffer(ctx context.Context, o *models.NegotiationOffer) error {
	query := `INSERT INTO negotiation_offers (negotiation_id, round_number, created_by, created_by_user_id,
		unit_price, currency, quantity, moq, total_price, delivery_days, dispatch_days, shipping_mode, incoterm,
		payment_terms, packaging, validity_date, special_conditions, remarks, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19)
		RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, o.NegotiationID, o.RoundNumber, o.CreatedBy, o.CreatedByUserID,
		o.UnitPrice, o.Currency, o.Quantity, o.MOQ, o.TotalPrice, o.DeliveryDays, o.DispatchDays, o.ShippingMode, o.Incoterm,
		o.PaymentTerms, o.Packaging, o.ValidityDate, o.SpecialConditions, o.Remarks, o.Status).
		Scan(&o.ID, &o.CreatedAt)
}

func (r *NegotiationRepository) ListOffers(ctx context.Context, negotiationID string) ([]models.NegotiationOffer, error) {
	rows, err := r.db.Query(ctx, `SELECT id, negotiation_id, round_number, created_by, created_by_user_id,
		unit_price, currency, quantity, moq, total_price, delivery_days, dispatch_days, shipping_mode, incoterm,
		payment_terms, packaging, validity_date, special_conditions, remarks, status, created_at
		FROM negotiation_offers WHERE negotiation_id = $1 ORDER BY round_number ASC, created_at ASC`, negotiationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.NegotiationOffer
	for rows.Next() {
		var o models.NegotiationOffer
		if err := rows.Scan(&o.ID, &o.NegotiationID, &o.RoundNumber, &o.CreatedBy, &o.CreatedByUserID,
			&o.UnitPrice, &o.Currency, &o.Quantity, &o.MOQ, &o.TotalPrice, &o.DeliveryDays, &o.DispatchDays, &o.ShippingMode, &o.Incoterm,
			&o.PaymentTerms, &o.Packaging, &o.ValidityDate, &o.SpecialConditions, &o.Remarks, &o.Status, &o.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, nil
}

func (r *NegotiationRepository) GetOffer(ctx context.Context, id string) (*models.NegotiationOffer, error) {
	var o models.NegotiationOffer
	err := r.db.QueryRow(ctx, `SELECT id, negotiation_id, round_number, created_by, created_by_user_id,
		unit_price, currency, quantity, moq, total_price, delivery_days, dispatch_days, shipping_mode, incoterm,
		payment_terms, packaging, validity_date, special_conditions, remarks, status, created_at
		FROM negotiation_offers WHERE id = $1`, id).Scan(&o.ID, &o.NegotiationID, &o.RoundNumber, &o.CreatedBy, &o.CreatedByUserID,
		&o.UnitPrice, &o.Currency, &o.Quantity, &o.MOQ, &o.TotalPrice, &o.DeliveryDays, &o.DispatchDays, &o.ShippingMode, &o.Incoterm,
		&o.PaymentTerms, &o.Packaging, &o.ValidityDate, &o.SpecialConditions, &o.Remarks, &o.Status, &o.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &o, nil
}

func (r *NegotiationRepository) SetOfferStatus(ctx context.Context, id string, status models.NegotiationOfferStatus) error {
	_, err := r.db.Exec(ctx, `UPDATE negotiation_offers SET status = $1 WHERE id = $2`, status, id)
	return err
}

func (r *NegotiationRepository) GetLatestOffer(ctx context.Context, negotiationID string) (*models.NegotiationOffer, error) {
	var o models.NegotiationOffer
	err := r.db.QueryRow(ctx, `SELECT id, negotiation_id, round_number, created_by, created_by_user_id,
		unit_price, currency, quantity, moq, total_price, delivery_days, dispatch_days, shipping_mode, incoterm,
		payment_terms, packaging, validity_date, special_conditions, remarks, status, created_at
		FROM negotiation_offers WHERE negotiation_id = $1 ORDER BY round_number DESC, created_at DESC LIMIT 1`, negotiationID).
		Scan(&o.ID, &o.NegotiationID, &o.RoundNumber, &o.CreatedBy, &o.CreatedByUserID,
			&o.UnitPrice, &o.Currency, &o.Quantity, &o.MOQ, &o.TotalPrice, &o.DeliveryDays, &o.DispatchDays, &o.ShippingMode, &o.Incoterm,
			&o.PaymentTerms, &o.Packaging, &o.ValidityDate, &o.SpecialConditions, &o.Remarks, &o.Status, &o.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &o, nil
}

// ---------------- Touching `quotations` (data only — no change to quotation module code) ----------------

// RejectQuotationDirect — importer rejects the very first quotation before any negotiation
// starts. Only allowed while the quotation is still 'pending' (enforced by the WHERE clause).
func (r *NegotiationRepository) RejectQuotationDirect(ctx context.Context, quotationID string) error {
	tag, err := r.db.Exec(ctx, `UPDATE quotations SET status = 'rejected', updated_at = now() WHERE id = $1 AND status = 'pending'`, quotationID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("quotation is not pending — cannot reject")
	}
	return nil
}

// LockQuotationFinal — once a negotiation reaches 'accepted', the underlying quotation's
// own negotiable columns are overwritten with the final agreed values, so the existing,
// completely unmodified TradeService.acceptQuotation() -> OrderService.CreateOrder() flow
// creates the order from exactly those final terms — never from an intermediate offer.
func (r *NegotiationRepository) LockQuotationFinal(ctx context.Context, quotationID string, offer *models.NegotiationOffer, extraTerms string) error {
	tag, err := r.db.Exec(ctx, `UPDATE quotations SET unit_price = $1, quantity = $2, total_amount = $3,
		validity_date = COALESCE($4, validity_date), terms = $5, updated_at = now()
		WHERE id = $6 AND status = 'pending'`,
		offer.UnitPrice, offer.Quantity, offer.TotalPrice, offer.ValidityDate, extraTerms, quotationID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("quotation is not in a lockable state (already accepted/rejected elsewhere)")
	}
	return nil
}

// ---------------- Admin ----------------

type AdminNegotiationRow struct {
	models.Negotiation
	RFQNumber    string `json:"rfq_number"`
	ImporterName string `json:"importer_name"`
	ExporterName string `json:"exporter_name"`
	ProductName  string `json:"product_name"`
	OfferCount   int    `json:"offer_count"`
}

type AdminNegotiationFilters struct {
	Status *string
	Search *string
}

func (r *NegotiationRepository) AdminList(ctx context.Context, f AdminNegotiationFilters) ([]AdminNegotiationRow, error) {
	query := `SELECT n.id, n.rfq_id, n.quotation_id, n.importer_id, n.exporter_id, n.status, n.current_round,
		n.created_at, n.updated_at, r.rfq_number, imp.full_name, exp.full_name, r.product_name,
		(SELECT COUNT(*) FROM negotiation_offers WHERE negotiation_id = n.id)
		FROM negotiations n
		JOIN rfqs r ON r.id = n.rfq_id
		JOIN users imp ON imp.id = n.importer_id
		JOIN users exp ON exp.id = n.exporter_id
		WHERE ($1::text IS NULL OR n.status::text = $1)
		  AND ($2::text IS NULL OR r.rfq_number ILIKE '%' || $2 || '%' OR r.product_name ILIKE '%' || $2 || '%'
		       OR imp.full_name ILIKE '%' || $2 || '%' OR exp.full_name ILIKE '%' || $2 || '%')
		ORDER BY n.updated_at DESC LIMIT 300`
	rows, err := r.db.Query(ctx, query, f.Status, f.Search)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminNegotiationRow
	for rows.Next() {
		var row AdminNegotiationRow
		if err := rows.Scan(&row.ID, &row.RFQID, &row.QuotationID, &row.ImporterID, &row.ExporterID, &row.Status, &row.CurrentRound,
			&row.CreatedAt, &row.UpdatedAt, &row.RFQNumber, &row.ImporterName, &row.ExporterName, &row.ProductName, &row.OfferCount); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, nil
}
