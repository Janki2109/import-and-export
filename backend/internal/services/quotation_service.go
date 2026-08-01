package services

import (
	"context"
	"fmt"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type QuotationService struct {
	quotationRepo *repository.QuotationRepository
	rfqRepo       *repository.RFQRepository
	orderService  *OrderService
	notification  *NotificationService
}

func NewQuotationService(quotationRepo *repository.QuotationRepository, rfqRepo *repository.RFQRepository, orderService *OrderService, notification *NotificationService) *QuotationService {
	return &QuotationService{quotationRepo: quotationRepo, rfqRepo: rfqRepo, orderService: orderService, notification: notification}
}

type SubmitQuotationInput struct {
	RFQID        string
	ExporterID   string
	UnitPrice    float64
	Quantity     float64
	ValidityDate time.Time
	Terms        *string
}

func (s *QuotationService) Submit(ctx context.Context, in SubmitQuotationInput) (*models.Quotation, error) {
	rfq, err := s.rfqRepo.GetByID(ctx, in.RFQID)
	if err != nil {
		return nil, err
	}
	if rfq.Status != models.RFQOpen && rfq.Status != models.RFQQuoted {
		return nil, fmt.Errorf("rfq is no longer open for quotations")
	}

	q := &models.Quotation{
		RFQID:        in.RFQID,
		ExporterID:   in.ExporterID,
		UnitPrice:    in.UnitPrice,
		Quantity:     in.Quantity,
		TotalAmount:  round2(in.UnitPrice * in.Quantity),
		ValidityDate: in.ValidityDate,
		Terms:        in.Terms,
		Status:       models.QuotationPending,
	}
	if err := s.quotationRepo.Create(ctx, q); err != nil {
		return nil, fmt.Errorf("submit quotation: %w", err)
	}
	if err := s.quotationRepo.MarkRFQQuoted(ctx, in.RFQID); err != nil {
		return nil, fmt.Errorf("mark rfq quoted: %w", err)
	}
	_ = s.notification.Send(ctx, rfq.ImporterID, "New Quotation Received", fmt.Sprintf("You received a quotation of ₹%.2f/unit for %s.", in.UnitPrice, rfq.ProductName), "order_update", &rfq.ID)
	return q, nil
}

func (s *QuotationService) ListForRFQ(ctx context.Context, rfqID, importerID string) ([]models.Quotation, error) {
	rfq, err := s.rfqRepo.GetByID(ctx, rfqID)
	if err != nil {
		return nil, err
	}
	if rfq.ImporterID != importerID {
		return nil, fmt.Errorf("not authorized to view quotations for this rfq")
	}
	return s.quotationRepo.ListByRFQ(ctx, rfqID)
}

func (s *QuotationService) ListMine(ctx context.Context, exporterID string) ([]models.Quotation, error) {
	return s.quotationRepo.ListByExporter(ctx, exporterID)
}

// Accept — importer accepts an exporter's quotation. This creates the actual Order + escrow row
// (reusing OrderService.CreateOrder so the escrow/payment lifecycle stays identical to a direct order),
// then links the quotation to that order and closes the RFQ.
func (s *QuotationService) Accept(ctx context.Context, quotationID, importerID string, deliveryAddress, notes *string) (*models.Order, error) {
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
		return nil, fmt.Errorf("not authorized to accept this quotation")
	}

	order, _, _, err := s.orderService.CreateOrder(ctx, CreateOrderInput{
		ImporterID:      importerID,
		ExporterID:      q.ExporterID,
		ProductName:     rfq.ProductName,
		HSNCode:         rfq.HSNCode,
		Quantity:        q.Quantity,
		Unit:            rfq.Unit,
		UnitPrice:       q.UnitPrice,
		DeliveryAddress: deliveryAddress,
		Notes:           notes,
	})
	if err != nil {
		return nil, fmt.Errorf("create order from quotation: %w", err)
	}

	if err := s.quotationRepo.Accept(ctx, quotationID, q.RFQID, order.ID); err != nil {
		return order, fmt.Errorf("order created but linking quotation failed: %w", err)
	}

	_ = s.notification.Send(ctx, q.ExporterID, "Quotation Accepted", fmt.Sprintf("Your quotation for %s was accepted — order %s created.", rfq.ProductName, order.OrderNumber), "order_update", &order.ID)
	return order, nil
}
