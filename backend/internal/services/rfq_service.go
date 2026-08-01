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

	// New RFQs are an open marketplace listing (any exporter can browse and quote), so
	// there's no single "assigned" exporter to notify — broadcast to every active exporter,
	// plus admin for visibility. Best-effort: a notification failure must never fail RFQ
	// creation itself.
	s.notifyExportersOfNewRFQ(ctx, rfq)
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

func (s *RFQService) ListOpen(ctx context.Context) ([]models.RFQ, error) {
	return s.rfqRepo.ListOpen(ctx, 50, 0)
}

func (s *RFQService) ListMine(ctx context.Context, importerID string) ([]models.RFQ, error) {
	return s.rfqRepo.ListByImporter(ctx, importerID, 50, 0)
}

func generateRFQNumber() string {
	year := time.Now().Year()
	return fmt.Sprintf("RFQ-%d-%06d", year, rand.Intn(999999))
}
