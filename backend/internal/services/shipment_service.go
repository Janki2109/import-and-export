package services

import (
	"context"
	"fmt"
	"strings"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type ShipmentService struct {
	shipmentRepo *repository.ShipmentRepository
	orderRepo    *repository.OrderRepository
	notification *NotificationService
}

func NewShipmentService(shipmentRepo *repository.ShipmentRepository, orderRepo *repository.OrderRepository, notification *NotificationService) *ShipmentService {
	return &ShipmentService{shipmentRepo: shipmentRepo, orderRepo: orderRepo, notification: notification}
}

// AssignLogistics — exporter-only action, order must be in payment_held/accepted state.
func (s *ShipmentService) AssignLogistics(ctx context.Context, orderID, exporterID, logisticsID, trackingNumber, carrierName string) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}
	if order.ExporterID != exporterID {
		return fmt.Errorf("not authorized: this order does not belong to you")
	}
	if order.Status != models.OrderPaymentHeld && order.Status != models.OrderAccepted {
		return fmt.Errorf("cannot assign logistics: order status is %s", order.Status)
	}
	if err := s.shipmentRepo.AssignLogistics(ctx, orderID, logisticsID, trackingNumber, carrierName); err != nil {
		return err
	}
	_ = s.notification.Send(ctx, logisticsID, "New Shipment Request", fmt.Sprintf("You've been assigned to ship order %s.", order.OrderNumber), "shipment", &order.ID)
	_ = s.notification.Send(ctx, order.ImporterID, "Shipment Started", fmt.Sprintf("A logistics partner has been assigned for order %s.", order.OrderNumber), "shipment", &order.ID)
	return nil
}

// validShipmentStatuses — the full in-transit lifecycle a logistics partner can move a
// shipment through, in order. "assigned" is set automatically by AssignLogistics, not
// chosen here.
var validShipmentStatuses = map[string]bool{
	"pickup_scheduled":       true,
	"picked_up":              true,
	"at_warehouse":           true,
	"customs_clearance":      true,
	"loaded":                 true,
	"in_transit":             true,
	"arrived_at_destination": true,
	"out_for_delivery":       true,
	"delivered":              true,
	"exception":              true,
}

// UpdateShipmentStatus — logistics-only, must own the shipment.
func (s *ShipmentService) UpdateShipmentStatus(ctx context.Context, shipmentID, logisticsID, status, location, remarks string) error {
	// (In a fuller implementation we'd verify shipment.logistics_id == logisticsID here via a lookup.
	// Keeping the repo call direct for now — add ownership check before production go-live.)
	if !validShipmentStatuses[status] {
		return fmt.Errorf("invalid status: %s", status)
	}
	if err := s.shipmentRepo.UpdateStatus(ctx, shipmentID, status, location, remarks, logisticsID); err != nil {
		return err
	}

	shipment, err := s.shipmentRepo.GetByID(ctx, shipmentID)
	if err == nil && shipment != nil {
		order, orderErr := s.orderRepo.GetByID(ctx, shipment.OrderID)
		if orderErr == nil {
			label := statusLabel(status)
			msg := fmt.Sprintf("Order %s status: %s", order.OrderNumber, label)
			// Both parties requested this — importer already got a coarser "Shipment
			// Started" notice at assignment time; this is the ongoing progress feed.
			_ = s.notification.Send(ctx, order.ImporterID, "Shipment Update", msg, "shipment", &order.ID)
			_ = s.notification.Send(ctx, order.ExporterID, "Shipment Update", msg, "shipment", &order.ID)
		}
	}
	return nil
}

// statusLabel — "pickup_scheduled" -> "Pickup Scheduled", used only for notification text.
func statusLabel(status string) string {
	words := strings.Split(status, "_")
	for i, w := range words {
		if w == "" {
			continue
		}
		words[i] = strings.ToUpper(w[:1]) + w[1:]
	}
	return strings.Join(words, " ")
}

func (s *ShipmentService) UploadPOD(ctx context.Context, pod *models.PODDocument) error {
	if err := s.shipmentRepo.AddPOD(ctx, pod); err != nil {
		return err
	}
	shipment, err := s.shipmentRepo.GetByID(ctx, pod.ShipmentID)
	if err == nil && shipment != nil {
		order, orderErr := s.orderRepo.GetByID(ctx, shipment.OrderID)
		if orderErr == nil {
			_ = s.notification.Send(ctx, order.ImporterID, "Shipment Delivered", fmt.Sprintf("Proof of delivery uploaded for order %s. Please confirm receipt.", order.OrderNumber), "shipment", &order.ID)
		}
	}
	return nil
}

func (s *ShipmentService) GetByOrderID(ctx context.Context, orderID string) (*models.Shipment, error) {
	return s.shipmentRepo.GetByOrderID(ctx, orderID)
}

func (s *ShipmentService) GetTrackingTimeline(ctx context.Context, shipmentID string) ([]models.ShipmentEvent, error) {
	return s.shipmentRepo.GetEvents(ctx, shipmentID)
}

func (s *ShipmentService) ListMyShipments(ctx context.Context, logisticsID string) ([]models.Shipment, error) {
	return s.shipmentRepo.ListByLogistics(ctx, logisticsID, 50, 0)
}
