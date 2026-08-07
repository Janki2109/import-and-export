package services

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type RFQService struct {
	rfqRepo      *repository.RFQRepository
	userRepo     *repository.UserRepository
	notification *NotificationService
}

func NewRFQService(rfqRepo *repository.RFQRepository, userRepo *repository.UserRepository, notification *NotificationService) *RFQService {
	return &RFQService{rfqRepo: rfqRepo, userRepo: userRepo, notification: notification}
}

type CreateRFQInput struct {
	ImporterID         string
	ProductName        string
	HSNCode            *string
	Quantity           float64
	Unit               string
	TargetPrice        *float64
	DestinationCountry string
	Description        *string
	// TargetExporterIDs — Journey 3's "request quotation" from a specific company profile.
	// Empty = unchanged open-marketplace broadcast behavior; non-empty = only these exporters
	// (plus admin) see this RFQ.
	TargetExporterIDs []string
}

func (s *RFQService) CreateRFQ(ctx context.Context, in CreateRFQInput) (*models.RFQ, error) {
	rfq := &models.RFQ{
		RFQNumber:          generateRFQNumber(),
		ImporterID:         in.ImporterID,
		ProductName:        in.ProductName,
		HSNCode:            in.HSNCode,
		Quantity:           in.Quantity,
		Unit:               in.Unit,
		TargetPrice:        in.TargetPrice,
		DestinationCountry: in.DestinationCountry,
		Description:        in.Description,
		Status:             models.RFQOpen,
	}
	if err := s.rfqRepo.Create(ctx, rfq); err != nil {
		return nil, fmt.Errorf("create rfq: %w", err)
	}

	if len(in.TargetExporterIDs) > 0 {
		// Journey 3: importer requested a quotation directly from specific companies' profiles.
		// Only those exporters see this RFQ (ListOpenForExporter enforces that) and only they're
		// notified — this is not a broadcast.
		if err := s.rfqRepo.AddTargets(ctx, rfq.ID, in.TargetExporterIDs); err != nil {
			return nil, fmt.Errorf("targeting rfq to exporters: %w", err)
		}
		title := "New RFQ Request"
		body := fmt.Sprintf("New RFQ %s for %s (qty %.0f %s) was sent directly to you — submit a quotation.", rfq.RFQNumber, rfq.ProductName, rfq.Quantity, rfq.Unit)
		for _, exporterID := range in.TargetExporterIDs {
			_ = s.notification.Send(ctx, exporterID, title, body, "rfq", &rfq.ID)
		}
	} else {
		// Untargeted RFQs are an open marketplace listing (any exporter can browse and quote), so
		// there's no single "assigned" exporter to notify — broadcast to every active exporter.
		// Best-effort: a notification failure must never fail RFQ creation itself.
		s.notifyExportersOfNewRFQ(ctx, rfq)
	}
	_ = s.notification.NotifyAdmin(ctx, "New RFQ Posted", fmt.Sprintf("RFQ %s posted for %s.", rfq.RFQNumber, rfq.ProductName), "rfq", &rfq.ID)

	return rfq, nil
}

func (s *RFQService) notifyExportersOfNewRFQ(ctx context.Context, rfq *models.RFQ) {
	role := "exporter"
	exporters, err := s.userRepo.ListByRole(ctx, &role)
	if err != nil {
		log.Printf("rfq: could not list exporters to notify for RFQ %s: %v", rfq.RFQNumber, err)
		return
	}
	title := "New RFQ Posted"
	body := fmt.Sprintf("New RFQ %s for %s (qty %.0f %s) — submit a quotation.", rfq.RFQNumber, rfq.ProductName, rfq.Quantity, rfq.Unit)
	for _, exporter := range exporters {
		_ = s.notification.Send(ctx, exporter.ID, title, body, "rfq", &rfq.ID)
	}
}

// SECURITY FIX (document ownership validation): previously had no authorization check —
// any authenticated user could view any RFQ by ID, including its TargetPrice, bypassing
// deliberate exporter-targeting (a competing exporter never sent the RFQ could still read the
// importer's target price). Now: the RFQ's own importer, an admin, or an exporter this RFQ is
// actually visible to (untargeted, or specifically targeted at them) can view it — the same
// rule ListOpenForExporter already enforces for browsing.
func (s *RFQService) GetByID(ctx context.Context, id, requesterID string, requesterRole models.UserRole) (*models.RFQ, error) {
	rfq, err := s.rfqRepo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if requesterRole == models.RoleAdmin || requesterID == rfq.ImporterID {
		return rfq, nil
	}
	if requesterRole == models.RoleExporter {
		visible, err := s.rfqRepo.IsVisibleToExporter(ctx, id, requesterID)
		if err != nil {
			return nil, err
		}
		if visible {
			return rfq, nil
		}
	}
	return nil, fmt.Errorf("not authorized to view this rfq")
}

func (s *RFQService) ListOpen(ctx context.Context, exporterID string) ([]models.RFQ, error) {
	return s.rfqRepo.ListOpenForExporter(ctx, exporterID, 50, 0)
}

func (s *RFQService) ListMine(ctx context.Context, importerID string) ([]models.RFQ, error) {
	return s.rfqRepo.ListByImporter(ctx, importerID, 50, 0)
}

// generateRFQNumber — BUG FIX (M-27): same widened-entropy fix as generateOrderNumber (see
// order_service.go) — the previous 6-digit rand.Intn(999999) suffix had a realistic collision
// window against a UNIQUE column.
func generateRFQNumber() string {
	year := time.Now().Year()
	return fmt.Sprintf("RFQ-%d-%d%06d", year, time.Now().UnixNano()%1000, secureRandInt(1000000000))
}
