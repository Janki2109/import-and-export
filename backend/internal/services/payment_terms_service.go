package services

import (
	"context"
	"fmt"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

// PaymentTermsService — Payment Terms & Milestone Escrow Engine. Additive module: reuses
// OrderRepository (read-only lookups) and inserts new ledger_entries rows on release
// (same generic table EscrowRepository already writes to); never touches orders or
// escrow_payments rows, so the existing single-payment escrow flow keeps working exactly
// as before for any order that doesn't opt into this module.
type PaymentTermsService struct {
	repo         *repository.PaymentTermsRepository
	orderRepo    *repository.OrderRepository
	auditRepo    *repository.AuditLogRepository
	notification *NotificationService
}

func NewPaymentTermsService(repo *repository.PaymentTermsRepository, orderRepo *repository.OrderRepository, auditRepo *repository.AuditLogRepository, notification *NotificationService) *PaymentTermsService {
	return &PaymentTermsService{repo: repo, orderRepo: orderRepo, auditRepo: auditRepo, notification: notification}
}

type MilestoneInput struct {
	Title         string
	Percentage    float64
	TriggerEvent  string
	ProofRequired bool
}

type SetupInput struct {
	OrderID         string
	PaymentModel    models.PaymentModel
	Currency        string
	Milestones      []MilestoneInput // required for milestone_escrow/advance_balance/custom
	LCNumber        *string
	LCBankName      *string
	LCExpiryDate    *time.Time
	OpenAccountDays *int
}

func defaultMilestones(model models.PaymentModel, openAccountDays *int) []MilestoneInput {
	switch model {
	case models.PaymentModelAdvance100:
		return []MilestoneInput{{Title: "Full Advance Payment", Percentage: 100, TriggerEvent: "manual_release", ProofRequired: false}}
	case models.PaymentModelLC:
		return []MilestoneInput{{Title: "Letter of Credit Payment", Percentage: 100, TriggerEvent: "manual_release", ProofRequired: false}}
	case models.PaymentModelOpenAccount:
		days := 30
		if openAccountDays != nil {
			days = *openAccountDays
		}
		return []MilestoneInput{{Title: fmt.Sprintf("Payment Due (%d Days After Shipment)", days), Percentage: 100, TriggerEvent: "manual_release", ProofRequired: false}}
	default:
		return nil
	}
}

func (s *PaymentTermsService) authorizeOrderParty(ctx context.Context, orderID, requesterID, requesterRole string) (*models.Order, error) {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, fmt.Errorf("order not found: %w", err)
	}
	if requesterRole == "admin" {
		return order, nil
	}
	if order.ImporterID != requesterID && order.ExporterID != requesterID {
		return nil, fmt.Errorf("not authorized for this order")
	}
	return order, nil
}

// Setup — creates the locked payment schedule for an order. Idempotent: returns existing
// terms if already set up. Percentages must sum to 100.
func (s *PaymentTermsService) Setup(ctx context.Context, actorID, actorRole string, in SetupInput) (*models.PaymentTerms, []models.PaymentMilestone, error) {
	order, err := s.authorizeOrderParty(ctx, in.OrderID, actorID, actorRole)
	if err != nil {
		return nil, nil, err
	}
	if existing, err := s.repo.GetByOrderID(ctx, in.OrderID); err == nil && existing != nil {
		ms, _ := s.repo.ListMilestones(ctx, existing.ID)
		return existing, ms, nil
	}

	milestones := in.Milestones
	if len(milestones) == 0 {
		milestones = defaultMilestones(in.PaymentModel, in.OpenAccountDays)
	}
	if len(milestones) == 0 {
		return nil, nil, fmt.Errorf("at least one milestone is required for this payment model")
	}
	var total float64
	for _, m := range milestones {
		total += m.Percentage
	}
	if total < 99.9 || total > 100.1 {
		return nil, nil, fmt.Errorf("milestone percentages must sum to 100, got %.2f", total)
	}

	currency := in.Currency
	if currency == "" {
		currency = "INR"
	}

	terms := &models.PaymentTerms{
		OrderID:         in.OrderID,
		PaymentModel:    in.PaymentModel,
		Currency:        currency,
		TotalAmount:     order.TotalAmount,
		LCNumber:        in.LCNumber,
		LCBankName:      in.LCBankName,
		LCExpiryDate:    in.LCExpiryDate,
		OpenAccountDays: in.OpenAccountDays,
		CreatedBy:       actorID,
	}
	if in.PaymentModel == models.PaymentModelLC {
		pending := models.LCPending
		terms.LCStatus = &pending
	}
	if err := s.repo.Create(ctx, terms); err != nil {
		return nil, nil, fmt.Errorf("create payment terms: %w", err)
	}

	var created []models.PaymentMilestone
	for i, m := range milestones {
		trigger := m.TriggerEvent
		if trigger == "" {
			trigger = "manual_release"
		}
		pm := &models.PaymentMilestone{
			PaymentTermID: terms.ID,
			ReleaseOrder:  i + 1,
			Title:         m.Title,
			Percentage:    m.Percentage,
			Amount:        order.TotalAmount * m.Percentage / 100,
			TriggerEvent:  trigger,
			ProofRequired: m.ProofRequired,
		}
		if err := s.repo.CreateMilestone(ctx, pm); err != nil {
			return nil, nil, fmt.Errorf("create milestone %q: %w", m.Title, err)
		}
		created = append(created, *pm)
	}

	_ = s.auditRepo.Record(ctx, actorID, "payment_terms.setup", "payment_terms", terms.ID, map[string]interface{}{
		"order_id": in.OrderID, "payment_model": in.PaymentModel, "milestone_count": len(created),
	})
	return terms, created, nil
}

func (s *PaymentTermsService) GetByOrderID(ctx context.Context, orderID string) (*models.PaymentTerms, []models.PaymentMilestone, error) {
	terms, err := s.repo.GetByOrderID(ctx, orderID)
	if err != nil {
		return nil, nil, err
	}
	ms, err := s.repo.ListMilestones(ctx, terms.ID)
	if err != nil {
		return nil, nil, err
	}
	return terms, ms, nil
}

func (s *PaymentTermsService) milestoneOrder(ctx context.Context, milestoneID string) (*models.PaymentMilestone, *models.PaymentTerms, *models.Order, error) {
	m, err := s.repo.GetMilestone(ctx, milestoneID)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("milestone not found: %w", err)
	}
	terms, err := s.repo.GetByID(ctx, m.PaymentTermID)
	if err != nil {
		return nil, nil, nil, err
	}
	order, err := s.orderRepo.GetByID(ctx, terms.OrderID)
	if err != nil {
		return nil, nil, nil, err
	}
	return m, terms, order, nil
}

// PayMilestone — importer self-declares payment for the next milestone in sequence (mirrors
// the existing self-declared "confirm payment" pattern; no gateway integration here either).
func (s *PaymentTermsService) PayMilestone(ctx context.Context, milestoneID, importerID string) error {
	m, terms, order, err := s.milestoneOrder(ctx, milestoneID)
	if err != nil {
		return err
	}
	if order.ImporterID != importerID {
		return fmt.Errorf("only the importer can pay this milestone")
	}
	all, err := s.repo.ListMilestones(ctx, terms.ID)
	if err != nil {
		return err
	}
	for _, other := range all {
		if other.ReleaseOrder < m.ReleaseOrder && other.Status == models.MilestonePending {
			return fmt.Errorf("previous milestone %q must be paid first", other.Title)
		}
	}
	if err := s.repo.MarkPaid(ctx, milestoneID); err != nil {
		return err
	}
	if !m.ProofRequired {
		_ = s.repo.MarkReadyForReview(ctx, milestoneID)
		_ = s.notification.NotifyAdmin(ctx, "Payment Pending Approval", fmt.Sprintf("Milestone %q ready for review on order %s", m.Title, order.OrderNumber), "payment_milestone", &milestoneID)
	}
	_ = s.auditRepo.Record(ctx, importerID, "payment_milestone.paid", "payment_milestone", milestoneID, map[string]interface{}{"amount": m.Amount})
	_ = s.notification.Send(ctx, order.ExporterID, "Payment Received", fmt.Sprintf("Importer paid milestone %q", m.Title), "payment_milestone", &milestoneID)
	return nil
}

// UploadProof — exporter attaches proof of completion for a paid milestone.
func (s *PaymentTermsService) UploadProof(ctx context.Context, milestoneID, exporterID, proofURL string) error {
	_, _, order, err := s.milestoneOrder(ctx, milestoneID)
	if err != nil {
		return err
	}
	if order.ExporterID != exporterID {
		return fmt.Errorf("only the exporter can upload proof for this milestone")
	}
	if err := s.repo.UploadProof(ctx, milestoneID, proofURL, exporterID); err != nil {
		return err
	}
	_ = s.auditRepo.Record(ctx, exporterID, "payment_milestone.proof_uploaded", "payment_milestone", milestoneID, map[string]interface{}{"proof_url": proofURL})
	_ = s.notification.NotifyAdmin(ctx, "Proof Uploaded", fmt.Sprintf("Proof uploaded for milestone on order %s", order.OrderNumber), "payment_milestone", &milestoneID)
	return nil
}

func (s *PaymentTermsService) Approve(ctx context.Context, milestoneID, adminID string, remarks *string) error {
	m, _, order, err := s.milestoneOrder(ctx, milestoneID)
	if err != nil {
		return err
	}
	if err := s.repo.Approve(ctx, milestoneID, adminID, remarks); err != nil {
		return err
	}
	_ = s.auditRepo.Record(ctx, adminID, "payment_milestone.approved", "payment_milestone", milestoneID, map[string]interface{}{"remarks": remarks})
	_ = s.notification.Send(ctx, order.ImporterID, "Milestone Approved", fmt.Sprintf("Milestone %q approved", m.Title), "payment_milestone", &milestoneID)
	_ = s.notification.Send(ctx, order.ExporterID, "Proof Approved", fmt.Sprintf("Milestone %q approved, awaiting release", m.Title), "payment_milestone", &milestoneID)
	return nil
}

func (s *PaymentTermsService) Reject(ctx context.Context, milestoneID, adminID string, remarks *string) error {
	m, _, order, err := s.milestoneOrder(ctx, milestoneID)
	if err != nil {
		return err
	}
	if err := s.repo.Reject(ctx, milestoneID, adminID, remarks); err != nil {
		return err
	}
	_ = s.auditRepo.Record(ctx, adminID, "payment_milestone.rejected", "payment_milestone", milestoneID, map[string]interface{}{"remarks": remarks})
	_ = s.notification.Send(ctx, order.ImporterID, "Milestone Rejected", fmt.Sprintf("Milestone %q was rejected", m.Title), "payment_milestone", &milestoneID)
	_ = s.notification.Send(ctx, order.ExporterID, "Proof Rejected — Re-upload Needed", fmt.Sprintf("Milestone %q needs re-upload", m.Title), "payment_milestone", &milestoneID)
	return nil
}

func (s *PaymentTermsService) Hold(ctx context.Context, milestoneID, adminID string, remarks *string) error {
	return s.repo.Hold(ctx, milestoneID, adminID, remarks)
}

func (s *PaymentTermsService) Unhold(ctx context.Context, milestoneID string) error {
	return s.repo.Unhold(ctx, milestoneID)
}

// Release — admin releases approved funds to the exporter's wallet (via ledger_entries).
func (s *PaymentTermsService) Release(ctx context.Context, milestoneID, adminID string) (*models.PaymentMilestone, error) {
	m, terms, order, err := s.milestoneOrder(ctx, milestoneID)
	if err != nil {
		return nil, err
	}
	released, err := s.repo.Release(ctx, milestoneID, order.ID, order.ExporterID, adminID)
	if err != nil {
		return nil, err
	}
	_ = s.auditRepo.Record(ctx, adminID, "payment_milestone.released", "payment_milestone", milestoneID, map[string]interface{}{"amount": m.Amount})
	_ = s.notification.Send(ctx, order.ExporterID, "Funds Credited", fmt.Sprintf("%s %.2f credited to your wallet for %q", terms.Currency, m.Amount, m.Title), "payment_milestone", &milestoneID)
	_ = s.notification.Send(ctx, order.ImporterID, "Milestone Released", fmt.Sprintf("Milestone %q released to exporter", m.Title), "payment_milestone", &milestoneID)

	all, err := s.repo.ListMilestones(ctx, terms.ID)
	if err == nil {
		complete := true
		for _, x := range all {
			if x.Status != models.MilestoneReleased {
				complete = false
				break
			}
		}
		if complete {
			_ = s.repo.MarkCompleted(ctx, terms.ID)
			_ = s.notification.Send(ctx, order.ImporterID, "Payment Completed", "All milestones for this order have been released", "payment_terms", &terms.ID)
		}
	}
	return released, nil
}

func (s *PaymentTermsService) UpdateLC(ctx context.Context, termsID, actorID, actorRole string, number, bank *string, expiry *string, status *models.LCStatus) error {
	terms, err := s.repo.GetByID(ctx, termsID)
	if err != nil {
		return err
	}
	if _, err := s.authorizeOrderParty(ctx, terms.OrderID, actorID, actorRole); err != nil {
		return err
	}
	return s.repo.UpdateLC(ctx, termsID, number, bank, expiry, status)
}

func (s *PaymentTermsService) AdminList(ctx context.Context, f repository.AdminPaymentFilters) ([]repository.AdminPaymentRow, error) {
	return s.repo.AdminList(ctx, f)
}

func (s *PaymentTermsService) AdminSummary(ctx context.Context) (*repository.AdminPaymentSummary, error) {
	return s.repo.AdminSummary(ctx)
}
