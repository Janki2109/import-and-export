package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type ComplianceService struct {
	repo         *repository.ComplianceRepository
	orderRepo    *repository.OrderRepository
	companyRepo  *repository.CompanyRepository
	shipmentRepo *repository.ShipmentRepository
	notification *NotificationService
	docSecurity  *DocumentSecurityService
}

func NewComplianceService(repo *repository.ComplianceRepository, orderRepo *repository.OrderRepository, companyRepo *repository.CompanyRepository, shipmentRepo *repository.ShipmentRepository, notification *NotificationService, docSecurity *DocumentSecurityService) *ComplianceService {
	return &ComplianceService{repo: repo, orderRepo: orderRepo, companyRepo: companyRepo, shipmentRepo: shipmentRepo, notification: notification, docSecurity: docSecurity}
}

// GenerateChecklist — called once, best-effort, right after an order is created (see
// OrderService.CreateOrder). Reads the real trade-lane facts already in the system
// (exporter's company country = origin, importer's company country = destination, the
// order's own HS code, and the importer's stated preferred_shipping_mode as a best-effort
// shipping mode signal — there is no per-order shipping-mode field anywhere else in the
// schema, and this module must not add one to the order-creation flow itself), matches
// them against compliance_rules, and copies every hit into order_compliance.
//
// If shipping mode is unknown (no company preference set), rules are matched ignoring the
// mode dimension entirely (safer to over-include than to silently skip a mandatory
// document because the mode wasn't known yet).
func (s *ComplianceService) GenerateChecklist(ctx context.Context, orderID string) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil || order == nil {
		return fmt.Errorf("compliance: order not found: %w", err)
	}

	var origin, destination, shippingMode *string
	if exp, err := s.companyRepo.GetByUserID(ctx, order.ExporterID); err == nil && exp != nil {
		origin = exp.Country
	}
	if imp, err := s.companyRepo.GetByUserID(ctx, order.ImporterID); err == nil && imp != nil {
		destination = imp.Country
		shippingMode = imp.PreferredShippingMode
	}

	rules, err := s.repo.MatchRules(ctx, origin, destination, order.HSNCode, shippingMode)
	if err != nil {
		return fmt.Errorf("compliance: matching rules: %w", err)
	}
	if err := s.repo.GenerateChecklist(ctx, orderID, rules); err != nil {
		return fmt.Errorf("compliance: generating checklist: %w", err)
	}

	// Notify each responsible party once, per role, that documents are required.
	notified := map[models.UserRole]bool{}
	for _, rule := range rules {
		if notified[rule.ResponsibleRole] {
			continue
		}
		notified[rule.ResponsibleRole] = true
		userID := ""
		switch rule.ResponsibleRole {
		case models.RoleImporter:
			userID = order.ImporterID
		case models.RoleExporter:
			userID = order.ExporterID
		default:
			continue // logistics isn't assigned yet at order-creation time
		}
		_ = s.notification.Send(ctx, userID, "Compliance Documents Required",
			fmt.Sprintf("Order %s requires compliance documents from you. Check the Compliance tab on the order.", order.OrderNumber),
			"compliance", &order.ID)
	}

	return nil
}

// authorize — an order's importer/exporter, its assigned logistics partner, or an admin
// may view/act on its compliance checklist. Anyone else is rejected.
func (s *ComplianceService) authorize(ctx context.Context, orderID, requesterID string, requesterRole models.UserRole) error {
	if requesterRole == models.RoleAdmin {
		return nil
	}
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil || order == nil {
		return fmt.Errorf("order not found")
	}
	if requesterID == order.ImporterID || requesterID == order.ExporterID {
		return nil
	}
	if requesterRole == models.RoleLogistics {
		shipment, err := s.shipmentRepo.GetByOrderID(ctx, orderID)
		if err == nil && shipment != nil && shipment.LogisticsID != nil && *shipment.LogisticsID == requesterID {
			return nil
		}
	}
	return fmt.Errorf("not authorized to view this order's compliance checklist")
}

func (s *ComplianceService) GetForOrder(ctx context.Context, orderID, requesterID string, requesterRole models.UserRole, baseURL string) ([]models.OrderCompliance, error) {
	if err := s.authorize(ctx, orderID, requesterID, requesterRole); err != nil {
		return nil, err
	}
	items, err := s.repo.ListForOrder(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if s.docSecurity != nil {
		for i := range items {
			if items[i].UploadedFile != nil && *items[i].UploadedFile != "" {
				resolved := s.docSecurity.ResolveStoredValue(*items[i].UploadedFile, baseURL)
				items[i].UploadedFile = &resolved
			}
		}
	}
	return items, nil
}

// ShipmentBlockStatus — informational: whether this order still has unmet mandatory
// compliance items, and which ones. Surfaced in the UI as "Shipment Blocked"; deliberately
// NOT enforced inside ShipmentService's assign/status-update endpoints, since changing
// those would mean modifying the existing logistics workflow, which this module must not do.
func (s *ComplianceService) ShipmentBlockStatus(ctx context.Context, orderID, requesterID string, requesterRole models.UserRole) (bool, []string, error) {
	if err := s.authorize(ctx, orderID, requesterID, requesterRole); err != nil {
		return false, nil, err
	}
	return s.repo.IsShipmentBlocked(ctx, orderID)
}

func (s *ComplianceService) UploadDocument(ctx context.Context, complianceID, uploaderID string, uploaderRole models.UserRole, fileURL string, remarks *string) error {
	item, err := s.repo.GetByID(ctx, complianceID)
	if err != nil {
		return err
	}
	if item == nil {
		return fmt.Errorf("compliance item not found")
	}
	if err := s.authorize(ctx, item.OrderID, uploaderID, uploaderRole); err != nil {
		return err
	}
	if item.ResponsibleRole != uploaderRole {
		return fmt.Errorf("this document must be uploaded by the %s, not the %s", item.ResponsibleRole, uploaderRole)
	}

	if err := s.repo.UploadDocument(ctx, complianceID, fileURL, uploaderID, remarks); err != nil {
		return err
	}

	order, _ := s.orderRepo.GetByID(ctx, item.OrderID)
	if order != nil {
		_ = s.notification.NotifyAdmin(ctx, "Compliance Document Uploaded",
			fmt.Sprintf("%s uploaded for order %s — awaiting your verification.", item.DocumentName, order.OrderNumber),
			"compliance", &order.ID)
	}
	return nil
}

func (s *ComplianceService) VerifyDocument(ctx context.Context, complianceID, adminID string) error {
	item, err := s.repo.GetByID(ctx, complianceID)
	if err != nil || item == nil {
		return fmt.Errorf("compliance item not found")
	}
	if err := s.repo.VerifyDocument(ctx, complianceID, adminID); err != nil {
		return err
	}
	s.notifyResponsibleParty(ctx, item, "Compliance Document Approved", fmt.Sprintf("%s has been verified.", item.DocumentName))
	s.maybeNotifyComplianceComplete(ctx, item.OrderID)
	return nil
}

func (s *ComplianceService) RejectDocument(ctx context.Context, complianceID, adminID, remarks string) error {
	item, err := s.repo.GetByID(ctx, complianceID)
	if err != nil || item == nil {
		return fmt.Errorf("compliance item not found")
	}
	if err := s.repo.RejectDocument(ctx, complianceID, adminID, remarks); err != nil {
		return err
	}
	s.notifyResponsibleParty(ctx, item, "Compliance Document Rejected", fmt.Sprintf("%s was rejected: %s. Please re-upload.", item.DocumentName, remarks))
	return nil
}

func (s *ComplianceService) notifyResponsibleParty(ctx context.Context, item *models.OrderCompliance, title, body string) {
	order, err := s.orderRepo.GetByID(ctx, item.OrderID)
	if err != nil || order == nil {
		return
	}
	var userID string
	switch item.ResponsibleRole {
	case models.RoleImporter:
		userID = order.ImporterID
	case models.RoleExporter:
		userID = order.ExporterID
	case models.RoleLogistics:
		if shipment, err := s.shipmentRepo.GetByOrderID(ctx, item.OrderID); err == nil && shipment != nil && shipment.LogisticsID != nil {
			userID = *shipment.LogisticsID
		}
	}
	if userID != "" {
		_ = s.notification.Send(ctx, userID, title, body, "compliance", &order.ID)
	}
}

// maybeNotifyComplianceComplete — once every mandatory item on an order is verified,
// notify importer + exporter that compliance is complete and the shipment is unblocked.
func (s *ComplianceService) maybeNotifyComplianceComplete(ctx context.Context, orderID string) {
	blocked, _, err := s.repo.IsShipmentBlocked(ctx, orderID)
	if err != nil || blocked {
		return
	}
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil || order == nil {
		return
	}
	msg := fmt.Sprintf("All mandatory compliance documents for order %s are verified. Shipment is unblocked.", order.OrderNumber)
	_ = s.notification.Send(ctx, order.ImporterID, "Compliance Completed", msg, "compliance", &order.ID)
	_ = s.notification.Send(ctx, order.ExporterID, "Compliance Completed", msg, "compliance", &order.ID)
}

func (s *ComplianceService) ListHistory(ctx context.Context, complianceID, requesterID string, requesterRole models.UserRole, baseURL string) ([]models.ComplianceDocumentHistory, error) {
	item, err := s.repo.GetByID(ctx, complianceID)
	if err != nil || item == nil {
		return nil, fmt.Errorf("compliance item not found")
	}
	if err := s.authorize(ctx, item.OrderID, requesterID, requesterRole); err != nil {
		return nil, err
	}
	history, err := s.repo.ListHistory(ctx, complianceID)
	if err != nil {
		return nil, err
	}
	if s.docSecurity != nil {
		for i := range history {
			history[i].FileURL = s.docSecurity.ResolveStoredValue(history[i].FileURL, baseURL)
		}
	}
	return history, nil
}

// ---------------- Rule management (admin-only) ----------------

func (s *ComplianceService) ListRules(ctx context.Context) ([]models.ComplianceRule, error) {
	return s.repo.ListRules(ctx)
}

func (s *ComplianceService) CreateRule(ctx context.Context, rule *models.ComplianceRule) error {
	return s.repo.CreateRule(ctx, rule)
}

func (s *ComplianceService) DeleteRule(ctx context.Context, id string) error {
	return s.repo.DeleteRule(ctx, id)
}

// ---------------- Admin Compliance Center ----------------

func (s *ComplianceService) AdminList(ctx context.Context, f repository.AdminComplianceFilters) ([]repository.AdminComplianceRow, error) {
	return s.repo.AdminList(ctx, f)
}

func (s *ComplianceService) Summary(ctx context.Context) (*repository.ComplianceSummary, error) {
	return s.repo.Summary(ctx)
}
