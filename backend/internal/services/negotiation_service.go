package services

import (
	"context"
	"fmt"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type NegotiationService struct {
	repo          *repository.NegotiationRepository
	rfqRepo       *repository.RFQRepository
	quotationRepo *repository.QuotationRepository
	auditRepo     *repository.AuditLogRepository
	notification  *NotificationService
}

func NewNegotiationService(repo *repository.NegotiationRepository, rfqRepo *repository.RFQRepository, quotationRepo *repository.QuotationRepository, auditRepo *repository.AuditLogRepository, notification *NotificationService) *NegotiationService {
	return &NegotiationService{repo: repo, rfqRepo: rfqRepo, quotationRepo: quotationRepo, auditRepo: auditRepo, notification: notification}
}

func (s *NegotiationService) audit(ctx context.Context, actorID, action, negotiationID string, metadata map[string]interface{}) {
	_ = s.auditRepo.Record(ctx, actorID, action, "negotiation", negotiationID, metadata)
}

// RejectQuotation — importer's direct "Reject Quote" choice on the very first quotation,
// before any negotiation is started. Only touches quotations.status (via the repository's
// isolated raw SQL — the quotation module's own code is never called or modified).
func (s *NegotiationService) RejectQuotation(ctx context.Context, quotationID, importerID string) error {
	q, err := s.quotationRepo.GetByID(ctx, quotationID)
	if err != nil {
		return err
	}
	rfq, err := s.rfqRepo.GetByID(ctx, q.RFQID)
	if err != nil {
		return err
	}
	if rfq.ImporterID != importerID {
		return fmt.Errorf("not authorized to reject this quotation")
	}
	if err := s.repo.RejectQuotationDirect(ctx, quotationID); err != nil {
		return err
	}
	_ = s.notification.Send(ctx, q.ExporterID, "Quotation Rejected", fmt.Sprintf("Your quotation for RFQ %s was rejected.", rfq.RFQNumber), "quotation", &q.ID)
	return nil
}

// StartNegotiation — importer's "Start Negotiation" choice. Creates the negotiation row
// plus a round-1 offer that mirrors the exporter's original quotation exactly (the
// "Initial Quote" timeline entry) — nothing about the quotation itself is touched yet.
func (s *NegotiationService) StartNegotiation(ctx context.Context, quotationID, importerID string) (*models.Negotiation, error) {
	q, err := s.quotationRepo.GetByID(ctx, quotationID)
	if err != nil {
		return nil, err
	}
	if q.Status != models.QuotationPending {
		return nil, fmt.Errorf("quotation is not pending (status: %s)", q.Status)
	}
	rfq, err := s.rfqRepo.GetByID(ctx, q.RFQID)
	if err != nil {
		return nil, err
	}
	if rfq.ImporterID != importerID {
		return nil, fmt.Errorf("not authorized to negotiate this quotation")
	}

	if existing, _ := s.repo.GetByQuotationID(ctx, quotationID); existing != nil {
		return existing, nil // idempotent — already started
	}

	negotiation := &models.Negotiation{
		RFQID: q.RFQID, QuotationID: quotationID, ImporterID: importerID, ExporterID: q.ExporterID,
		Status: models.NegotiationOpen, CurrentRound: 1,
	}
	if err := s.repo.Create(ctx, negotiation); err != nil {
		return nil, err
	}

	validity := q.ValidityDate
	initialOffer := &models.NegotiationOffer{
		NegotiationID: negotiation.ID, RoundNumber: 1, CreatedBy: models.PartyExporter, CreatedByUserID: q.ExporterID,
		UnitPrice: q.UnitPrice, Currency: "INR", Quantity: q.Quantity, TotalPrice: q.TotalAmount,
		ValidityDate: &validity, Remarks: q.Terms, Status: models.OfferPending,
	}
	if err := s.repo.CreateOffer(ctx, initialOffer); err != nil {
		return negotiation, err
	}

	s.audit(ctx, importerID, "negotiation.started", negotiation.ID, map[string]interface{}{"quotation_id": quotationID})
	_ = s.notification.Send(ctx, q.ExporterID, "Negotiation Started", fmt.Sprintf("Importer wants to negotiate your quotation for RFQ %s.", rfq.RFQNumber), "negotiation", &negotiation.ID)
	return negotiation, nil
}

// authorize — only the negotiation's own importer/exporter, or an admin, may act on it.
func (s *NegotiationService) authorize(n *models.Negotiation, requesterID string, requesterRole models.UserRole) error {
	if requesterRole == models.RoleAdmin {
		return nil
	}
	if requesterID == n.ImporterID || requesterID == n.ExporterID {
		return nil
	}
	return fmt.Errorf("not authorized for this negotiation")
}

func (s *NegotiationService) partyOf(n *models.Negotiation, requesterID string) models.NegotiationParty {
	if requesterID == n.ExporterID {
		return models.PartyExporter
	}
	return models.PartyImporter
}

type OfferInput struct {
	UnitPrice         float64
	Currency          string
	Quantity          float64
	MOQ               *float64
	DeliveryDays      *int
	DispatchDays      *int
	ShippingMode      *string
	Incoterm          *string
	PaymentTerms      *string
	Packaging         *string
	ValidityDate      *time.Time
	SpecialConditions *string
	Remarks           *string
}

// CounterOffer — either party submits the next round. Rejects if it's not their turn
// (you cannot counter your own still-pending offer — the other party must respond first).
func (s *NegotiationService) CounterOffer(ctx context.Context, negotiationID, actorID string, actorRole models.UserRole, in OfferInput) (*models.NegotiationOffer, error) {
	n, err := s.repo.GetByID(ctx, negotiationID)
	if err != nil || n == nil {
		return nil, fmt.Errorf("negotiation not found")
	}
	if err := s.authorize(n, actorID, actorRole); err != nil {
		return nil, err
	}
	if n.Status != models.NegotiationOpen {
		return nil, fmt.Errorf("negotiation is not open (status: %s)", n.Status)
	}

	latest, err := s.repo.GetLatestOffer(ctx, negotiationID)
	if err != nil {
		return nil, err
	}
	actingParty := s.partyOf(n, actorID)
	if latest != nil && latest.CreatedBy == actingParty {
		return nil, fmt.Errorf("waiting for the other party to respond to your last offer")
	}
	if latest != nil {
		_ = s.repo.SetOfferStatus(ctx, latest.ID, models.OfferCountered)
	}

	round, err := s.repo.IncrementRound(ctx, negotiationID)
	if err != nil {
		return nil, err
	}

	total := in.UnitPrice * in.Quantity
	currency := in.Currency
	if currency == "" {
		currency = "INR"
	}
	offer := &models.NegotiationOffer{
		NegotiationID: negotiationID, RoundNumber: round, CreatedBy: actingParty, CreatedByUserID: actorID,
		UnitPrice: in.UnitPrice, Currency: currency, Quantity: in.Quantity, MOQ: in.MOQ, TotalPrice: total,
		DeliveryDays: in.DeliveryDays, DispatchDays: in.DispatchDays, ShippingMode: in.ShippingMode, Incoterm: in.Incoterm,
		PaymentTerms: in.PaymentTerms, Packaging: in.Packaging, ValidityDate: in.ValidityDate,
		SpecialConditions: in.SpecialConditions, Remarks: in.Remarks, Status: models.OfferPending,
	}
	if err := s.repo.CreateOffer(ctx, offer); err != nil {
		return nil, err
	}

	s.audit(ctx, actorID, "negotiation.counter_offer", negotiationID, map[string]interface{}{"round": round, "unit_price": in.UnitPrice, "quantity": in.Quantity})

	recipient := n.ExporterID
	if actingParty == models.PartyExporter {
		recipient = n.ImporterID
	}
	_ = s.notification.Send(ctx, recipient, "Counter Offer Received", fmt.Sprintf("Round %d counter offer received — please review.", round), "negotiation", &negotiationID)
	return offer, nil
}

// AcceptOffer — accepting the other party's current offer ends the negotiation as
// 'accepted', locks the final agreed terms into the quotation, and notifies both sides.
// You cannot accept your own offer.
func (s *NegotiationService) AcceptOffer(ctx context.Context, negotiationID, actorID string, actorRole models.UserRole) error {
	n, err := s.repo.GetByID(ctx, negotiationID)
	if err != nil || n == nil {
		return fmt.Errorf("negotiation not found")
	}
	if err := s.authorize(n, actorID, actorRole); err != nil {
		return err
	}
	if n.Status != models.NegotiationOpen {
		return fmt.Errorf("negotiation is not open (status: %s)", n.Status)
	}

	latest, err := s.repo.GetLatestOffer(ctx, negotiationID)
	if err != nil || latest == nil {
		return fmt.Errorf("no offer to accept")
	}
	actingParty := s.partyOf(n, actorID)
	if latest.CreatedBy == actingParty {
		return fmt.Errorf("you cannot accept your own offer — waiting for the other party")
	}

	if err := s.repo.SetOfferStatus(ctx, latest.ID, models.OfferAccepted); err != nil {
		return err
	}
	if err := s.repo.UpdateStatus(ctx, negotiationID, models.NegotiationAccepted); err != nil {
		return err
	}

	extraTerms := formatFinalTerms(latest)
	if err := s.repo.LockQuotationFinal(ctx, n.QuotationID, latest, extraTerms); err != nil {
		return fmt.Errorf("negotiation accepted but locking final quotation failed: %w", err)
	}

	s.audit(ctx, actorID, "negotiation.accepted", negotiationID, map[string]interface{}{"final_offer_id": latest.ID})

	msg := "Agreement reached. The final quotation is locked and ready to accept as an order."
	_ = s.notification.Send(ctx, n.ImporterID, "Final Offer Ready", msg, "negotiation", &n.ID)
	_ = s.notification.Send(ctx, n.ExporterID, "Offer Accepted", msg, "negotiation", &n.ID)
	return nil
}

func formatFinalTerms(o *models.NegotiationOffer) string {
	terms := ""
	if o.ShippingMode != nil {
		terms += fmt.Sprintf("Shipping Mode: %s. ", *o.ShippingMode)
	}
	if o.Incoterm != nil {
		terms += fmt.Sprintf("Incoterm: %s. ", *o.Incoterm)
	}
	if o.PaymentTerms != nil {
		terms += fmt.Sprintf("Payment Terms: %s. ", *o.PaymentTerms)
	}
	if o.Packaging != nil {
		terms += fmt.Sprintf("Packaging: %s. ", *o.Packaging)
	}
	if o.DeliveryDays != nil {
		terms += fmt.Sprintf("Delivery: %d days. ", *o.DeliveryDays)
	}
	if o.DispatchDays != nil {
		terms += fmt.Sprintf("Dispatch: %d days. ", *o.DispatchDays)
	}
	if o.SpecialConditions != nil && *o.SpecialConditions != "" {
		terms += fmt.Sprintf("Special Conditions: %s. ", *o.SpecialConditions)
	}
	if o.Remarks != nil && *o.Remarks != "" {
		terms += *o.Remarks
	}
	return terms
}

// RejectOffer — rejects the other party's current offer, ending the negotiation as
// 'rejected'. The quotation itself is left untouched (still 'pending') so the RFQ simply
// returns to the quotation stage, as specified.
func (s *NegotiationService) RejectOffer(ctx context.Context, negotiationID, actorID string, actorRole models.UserRole) error {
	n, err := s.repo.GetByID(ctx, negotiationID)
	if err != nil || n == nil {
		return fmt.Errorf("negotiation not found")
	}
	if err := s.authorize(n, actorID, actorRole); err != nil {
		return err
	}
	if n.Status != models.NegotiationOpen {
		return fmt.Errorf("negotiation is not open (status: %s)", n.Status)
	}

	latest, err := s.repo.GetLatestOffer(ctx, negotiationID)
	if err == nil && latest != nil {
		_ = s.repo.SetOfferStatus(ctx, latest.ID, models.OfferRejected)
	}
	if err := s.repo.UpdateStatus(ctx, negotiationID, models.NegotiationRejected); err != nil {
		return err
	}

	s.audit(ctx, actorID, "negotiation.rejected", negotiationID, nil)
	other := n.ExporterID
	if s.partyOf(n, actorID) == models.PartyExporter {
		other = n.ImporterID
	}
	_ = s.notification.Send(ctx, other, "Offer Rejected", "The negotiation was rejected. It is now closed.", "negotiation", &n.ID)
	return nil
}

// CloseNegotiation — either party voluntarily cancels ("Cancel Negotiation").
func (s *NegotiationService) CloseNegotiation(ctx context.Context, negotiationID, actorID string, actorRole models.UserRole) error {
	n, err := s.repo.GetByID(ctx, negotiationID)
	if err != nil || n == nil {
		return fmt.Errorf("negotiation not found")
	}
	if err := s.authorize(n, actorID, actorRole); err != nil {
		return err
	}
	if err := s.repo.UpdateStatus(ctx, negotiationID, models.NegotiationClosed); err != nil {
		return err
	}
	s.audit(ctx, actorID, "negotiation.closed", negotiationID, nil)
	other := n.ExporterID
	if s.partyOf(n, actorID) == models.PartyExporter {
		other = n.ImporterID
	}
	_ = s.notification.Send(ctx, other, "Negotiation Closed", "The other party closed this negotiation.", "negotiation", &n.ID)
	return nil
}

// ForceClose — admin override, bypasses party authorization entirely.
func (s *NegotiationService) ForceClose(ctx context.Context, negotiationID, adminID string) error {
	n, err := s.repo.GetByID(ctx, negotiationID)
	if err != nil || n == nil {
		return fmt.Errorf("negotiation not found")
	}
	if err := s.repo.UpdateStatus(ctx, negotiationID, models.NegotiationClosed); err != nil {
		return err
	}
	s.audit(ctx, adminID, "negotiation.force_closed", negotiationID, nil)
	_ = s.notification.Send(ctx, n.ImporterID, "Negotiation Closed", "An admin closed this negotiation.", "negotiation", &n.ID)
	_ = s.notification.Send(ctx, n.ExporterID, "Negotiation Closed", "An admin closed this negotiation.", "negotiation", &n.ID)
	return nil
}

func (s *NegotiationService) GetByID(ctx context.Context, id, requesterID string, requesterRole models.UserRole) (*models.Negotiation, error) {
	n, err := s.repo.GetByID(ctx, id)
	if err != nil || n == nil {
		return nil, fmt.Errorf("negotiation not found")
	}
	if err := s.authorize(n, requesterID, requesterRole); err != nil {
		return nil, err
	}
	return n, nil
}

func (s *NegotiationService) GetTimeline(ctx context.Context, id, requesterID string, requesterRole models.UserRole) ([]models.NegotiationOffer, error) {
	if _, err := s.GetByID(ctx, id, requesterID, requesterRole); err != nil {
		return nil, err
	}
	return s.repo.ListOffers(ctx, id)
}

func (s *NegotiationService) ListMine(ctx context.Context, userID string, role models.UserRole) ([]models.Negotiation, error) {
	return s.repo.ListMine(ctx, userID, role)
}

// SECURITY FIX (document ownership validation): previously had no authorization check —
// any authenticated user could look up the negotiation record for any quotation just by
// knowing/guessing a quotationID, leaking the deal's parties and status. Now uses the same
// authorize() check GetByID/GetTimeline already had.
func (s *NegotiationService) GetByQuotationID(ctx context.Context, quotationID, requesterID string, requesterRole models.UserRole) (*models.Negotiation, error) {
	n, err := s.repo.GetByQuotationID(ctx, quotationID)
	if err != nil || n == nil {
		return nil, fmt.Errorf("negotiation not found")
	}
	if err := s.authorize(n, requesterID, requesterRole); err != nil {
		return nil, err
	}
	return n, nil
}

// ---------------- Admin ----------------

func (s *NegotiationService) AdminList(ctx context.Context, f repository.AdminNegotiationFilters) ([]repository.AdminNegotiationRow, error) {
	return s.repo.AdminList(ctx, f)
}
