package services

import (
	"context"
	"fmt"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type DisputeService struct {
	disputeRepo  *repository.DisputeRepository
	orderRepo    *repository.OrderRepository
	escrowRepo   *repository.EscrowRepository
	userRepo     *repository.UserRepository
	auditRepo    *repository.AuditLogRepository
	orderSvc     *OrderService
	notification *NotificationService
}

func NewDisputeService(disputeRepo *repository.DisputeRepository, orderRepo *repository.OrderRepository, escrowRepo *repository.EscrowRepository, userRepo *repository.UserRepository, auditRepo *repository.AuditLogRepository, orderSvc *OrderService, notification *NotificationService) *DisputeService {
	return &DisputeService{disputeRepo: disputeRepo, orderRepo: orderRepo, escrowRepo: escrowRepo, userRepo: userRepo, auditRepo: auditRepo, orderSvc: orderSvc, notification: notification}
}

// Raise — importer or exporter on the order flags a problem. Moves the order to 'disputed',
// which the auto-release cron already checks for and skips, freezing escrow until an admin resolves it.
func (s *DisputeService) Raise(ctx context.Context, orderID, raisedBy, reason string) (*models.Dispute, error) {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if raisedBy != order.ImporterID && raisedBy != order.ExporterID {
		return nil, fmt.Errorf("not authorized to raise a dispute on this order")
	}
	// LOGIC FIX (M-11): OrderCreated (unpaid — no escrow held yet) was previously not in this
	// blocklist, so a dispute could be raised on an order before any payment happened. The order
	// would flip to 'disputed' and then be permanently stuck: it could never be paid (payment
	// entry points require status == OrderCreated), MarkRefunded would reject it ("not in a
	// refundable state" — escrow is still 'created', never held), and release requires a
	// delivery that can never happen on an order nobody paid for. A dispute now requires the
	// order to have actually progressed past unpaid.
	switch order.Status {
	case models.OrderCreated, models.OrderPaymentReleased, models.OrderRefunded, models.OrderCancelled, models.OrderDisputed:
		return nil, fmt.Errorf("cannot raise a dispute on an order with status: %s", order.Status)
	}

	existing, err := s.disputeRepo.GetOpenByOrderID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if existing != nil {
		return nil, fmt.Errorf("an open dispute already exists for this order")
	}

	dispute := &models.Dispute{OrderID: orderID, RaisedBy: raisedBy, Reason: reason}
	if err := s.disputeRepo.Create(ctx, dispute); err != nil {
		return nil, fmt.Errorf("raise dispute: %w", err)
	}
	if err := s.orderRepo.UpdateStatus(ctx, orderID, models.OrderDisputed); err != nil {
		return nil, fmt.Errorf("mark order disputed: %w", err)
	}

	counterparty := order.ExporterID
	if raisedBy == order.ExporterID {
		counterparty = order.ImporterID
	}
	_ = s.notification.Send(ctx, counterparty, "Dispute Raised", fmt.Sprintf("A dispute was raised on order %s. Escrow is frozen pending review.", order.OrderNumber), "escrow", &order.ID)
	_ = s.notification.NotifyAdmin(ctx, "Dispute Open", fmt.Sprintf("Order %s: dispute raised — payment release is locked until this is resolved.", order.OrderNumber), "escrow", &order.ID)
	return dispute, nil
}

func (s *DisputeService) ListOpen(ctx context.Context) ([]models.Dispute, error) {
	return s.disputeRepo.ListOpen(ctx)
}

func (s *DisputeService) ListMine(ctx context.Context, userID string) ([]models.Dispute, error) {
	return s.disputeRepo.ListByUser(ctx, userID)
}

// Resolve — admin decides in favor of the importer (refund) or the exporter (release).
// resolution must be "refund" or "release".
func (s *DisputeService) Resolve(ctx context.Context, disputeID, adminID, resolution, notes string) error {
	dispute, err := s.disputeRepo.GetByID(ctx, disputeID)
	if err != nil {
		return err
	}
	if dispute.Status != "open" {
		return fmt.Errorf("dispute is already %s", dispute.Status)
	}

	if resolution != "refund" && resolution != "release" {
		return fmt.Errorf("resolution must be 'refund' or 'release'")
	}

	// BUG FIX (H-12): previously moved money FIRST and closed the dispute row second, with no
	// shared transaction — if the second write failed (DB blip etc), the money had already
	// moved but the dispute stayed 'open' forever: a retry then failed too (MarkRefunded/release
	// reject an already-refunded/released escrow as "not in a refundable state"), permanently
	// blocking ConfirmDeliveryAndRelease on that order via the open-dispute guard. The dispute
	// row is now closed FIRST — if that fails, nothing else has happened yet (safe to retry). If
	// the subsequent money-move fails, the dispute is reopened so the state stays consistent
	// rather than silently claiming "resolved" while no money actually moved.
	if err := s.disputeRepo.Resolve(ctx, disputeID, adminID, "resolved", notes); err != nil {
		return err
	}

	switch resolution {
	case "refund":
		order, err := s.orderRepo.GetByID(ctx, dispute.OrderID)
		if err != nil {
			_ = s.disputeRepo.Reopen(ctx, disputeID)
			return fmt.Errorf("look up order for refund: %w", err)
		}
		if err := s.escrowRepo.MarkRefunded(ctx, dispute.OrderID, order.ImporterID); err != nil {
			_ = s.disputeRepo.Reopen(ctx, disputeID)
			return fmt.Errorf("refund importer: %w", err)
		}
	case "release":
		if err := s.orderSvc.ConfirmDeliveryAndRelease(ctx, dispute.OrderID, adminID, false); err != nil {
			_ = s.disputeRepo.Reopen(ctx, disputeID)
			return fmt.Errorf("release to exporter: %w", err)
		}
	}
	_ = s.auditRepo.Record(ctx, adminID, "dispute.resolve", "dispute", disputeID, map[string]interface{}{"resolution": resolution, "notes": notes})

	if order, err := s.orderRepo.GetByID(ctx, dispute.OrderID); err == nil {
		outcome := "Payment released to exporter."
		if resolution == "refund" {
			outcome = "Payment refunded to importer."
		}
		_ = s.notification.Send(ctx, order.ImporterID, "Dispute Resolved", fmt.Sprintf("Dispute on order %s resolved: %s", order.OrderNumber, outcome), "escrow", &order.ID)
		_ = s.notification.Send(ctx, order.ExporterID, "Dispute Resolved", fmt.Sprintf("Dispute on order %s resolved: %s", order.OrderNumber, outcome), "escrow", &order.ID)
	}
	return nil
}
