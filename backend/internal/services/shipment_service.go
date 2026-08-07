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
	compliance   *ComplianceService
	notification *NotificationService
}

func NewShipmentService(shipmentRepo *repository.ShipmentRepository, orderRepo *repository.OrderRepository, compliance *ComplianceService, notification *NotificationService) *ShipmentService {
	return &ShipmentService{shipmentRepo: shipmentRepo, orderRepo: orderRepo, compliance: compliance, notification: notification}
}

// AssignLogistics — exporter-only action, order must be in payment_held/accepted state.
//
// BUG FIX (Journey 6): "compliance should block shipment if incomplete" was built
// (ComplianceService.ShipmentBlockStatus) but never actually invoked from this flow — any
// order could be assigned to a logistics partner regardless of outstanding mandatory
// compliance documents. Now blocks assignment (not later stages — those still aren't
// touched, keeping the change scoped) until every mandatory item is verified.
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
	// FAIL-CLOSED FIX (M-22): previously "err == nil && blocked" meant any error from the
	// compliance check silently SKIPPED it — the exact "BUG FIX (Journey 6)" this function's own
	// comment says was being addressed. A lookup error now blocks assignment too, rather than
	// defaulting to "assume compliant".
	blocked, missing, cerr := s.compliance.ShipmentBlockStatus(ctx, orderID, exporterID, models.RoleExporter)
	if cerr != nil {
		return fmt.Errorf("could not verify compliance status, please retry: %w", cerr)
	}
	if blocked {
		return fmt.Errorf("cannot assign logistics: mandatory compliance documents outstanding: %s", strings.Join(missing, ", "))
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

// shipmentStatusOrder — BUG FIX (M-26): the map above was accepted as-is with no ordering
// check despite its own comment saying "in order" — a partner could previously post "delivered"
// immediately after assignment (skipping straight to delivered_at set / order marked delivered
// / POD unlocked with zero actual movement), or post an earlier stage AFTER a later one,
// permanently desyncing shipment and order state. "exception" is intentionally excluded from
// the ordering check — it can be reported at any stage.
var shipmentStatusOrder = map[string]int{
	"pickup_scheduled":       1,
	"picked_up":              2,
	"at_warehouse":           3,
	"customs_clearance":      4,
	"loaded":                 5,
	"in_transit":             6,
	"arrived_at_destination": 7,
	"out_for_delivery":       8,
	"delivered":              9,
}

// UpdateShipmentStatus — logistics-only, must own the shipment (enforced by the WHERE clause
// in ShipmentRepository.UpdateStatus, not here).
func (s *ShipmentService) UpdateShipmentStatus(ctx context.Context, shipmentID, logisticsID, status, location, remarks string) error {
	if !validShipmentStatuses[status] {
		return fmt.Errorf("invalid status: %s", status)
	}
	if newRank, ok := shipmentStatusOrder[status]; ok {
		current, err := s.shipmentRepo.GetByID(ctx, shipmentID)
		if err != nil {
			return err
		}
		if currentRank, ok := shipmentStatusOrder[string(current.Status)]; ok && newRank < currentRank {
			return fmt.Errorf("cannot move shipment status backward from %s to %s", current.Status, status)
		}
		if currentRank, ok := shipmentStatusOrder[string(current.Status)]; ok && newRank > currentRank+1 {
			return fmt.Errorf("cannot skip shipment stages: current status is %s, next expected stage is required before %s", current.Status, status)
		}
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

// BUG FIX (Journey 6): previously accepted a POD upload from ANY logistics-role user for ANY
// shipment_id, not just the shipment's own assigned partner — mirrors the same gap C9 fixed
// for UpdateShipmentStatus.
func (s *ShipmentService) UploadPOD(ctx context.Context, pod *models.PODDocument) error {
	shipment, err := s.shipmentRepo.GetByID(ctx, pod.ShipmentID)
	if err != nil {
		return err
	}
	if shipment == nil {
		return fmt.Errorf("shipment not found")
	}
	if shipment.LogisticsID == nil || *shipment.LogisticsID != pod.UploadedBy {
		return fmt.Errorf("not authorized: this shipment is not assigned to you")
	}

	if err := s.shipmentRepo.AddPOD(ctx, pod); err != nil {
		return err
	}
	order, orderErr := s.orderRepo.GetByID(ctx, shipment.OrderID)
	if orderErr == nil {
		_ = s.notification.Send(ctx, order.ImporterID, "Shipment Delivered", fmt.Sprintf("Proof of delivery uploaded for order %s. Please confirm receipt.", order.OrderNumber), "shipment", &order.ID)
	}
	return nil
}

// SECURITY FIX (document/data ownership validation): GetByOrderID and GetTrackingTimeline
// previously had no authorization check at all — any authenticated user could view any order's
// shipment/tracking details (pickup/delivery addresses, carrier, POD) just by knowing/guessing
// an order_id or shipment_id. Both now require the requester to be that order's own
// importer/exporter, its assigned logistics partner, or an admin.
func (s *ShipmentService) authorizeOrderAccess(ctx context.Context, orderID, requesterID, requesterRole string) error {
	if requesterRole == "admin" {
		return nil
	}
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return fmt.Errorf("order not found")
	}
	if requesterID == order.ImporterID || requesterID == order.ExporterID {
		return nil
	}
	if requesterRole == "logistics" {
		shipment, err := s.shipmentRepo.GetByOrderID(ctx, orderID)
		if err == nil && shipment != nil && shipment.LogisticsID != nil && *shipment.LogisticsID == requesterID {
			return nil
		}
	}
	return fmt.Errorf("not authorized to view this order's shipment details")
}

func (s *ShipmentService) GetByOrderID(ctx context.Context, orderID, requesterID, requesterRole string) (*models.Shipment, error) {
	if err := s.authorizeOrderAccess(ctx, orderID, requesterID, requesterRole); err != nil {
		return nil, err
	}
	return s.shipmentRepo.GetByOrderID(ctx, orderID)
}

// GetTrackingTimeline — authorization is via the shipment's own order (looked up first) rather
// than shipmentID directly, since that's what carries importer/exporter/logistics identity.
func (s *ShipmentService) GetTrackingTimeline(ctx context.Context, shipmentID, requesterID, requesterRole string) ([]models.ShipmentEvent, error) {
	shipment, err := s.shipmentRepo.GetByID(ctx, shipmentID)
	if err != nil {
		return nil, fmt.Errorf("shipment not found")
	}
	if err := s.authorizeOrderAccess(ctx, shipment.OrderID, requesterID, requesterRole); err != nil {
		return nil, err
	}
	return s.shipmentRepo.GetEvents(ctx, shipmentID)
}

func (s *ShipmentService) ListMyShipments(ctx context.Context, logisticsID string) ([]models.Shipment, error) {
	return s.shipmentRepo.ListByLogistics(ctx, logisticsID, 50, 0)
}
