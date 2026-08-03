package services

import (
	"context"
	"fmt"
	"log"
	"math/rand"
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

func (s *RFQService) GetByID(ctx context.Context, id string) (*models.RFQ, error) {
	return s.rfqRepo.GetByID(ctx, id)
}

func (s *RFQService) ListOpen(ctx context.Context, exporterID string) ([]models.RFQ, error) {
	return s.rfqRepo.ListOpenForExporter(ctx, exporterID, 50, 0)
}

func (s *RFQService) ListMine(ctx context.Context, importerID string) ([]models.RFQ, error) {
	return s.rfqRepo.ListByImporter(ctx, importerID, 50, 0)
}

func generateRFQNumber() string {
	year := time.Now().Year()
	return fmt.Sprintf("RFQ-%d-%06d", year, rand.Intn(999999))
}
