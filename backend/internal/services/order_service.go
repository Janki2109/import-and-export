package services

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/upi"
)

type OrderService struct {
	orderRepo    *repository.OrderRepository
	escrowRepo   *repository.EscrowRepository
	auditRepo    *repository.AuditLogRepository
	disputeRepo  *repository.DisputeRepository
	kycRepo      *repository.KYCRepository
	cfg          *config.Config
	notification *NotificationService
	compliance   *ComplianceService
}

func NewOrderService(orderRepo *repository.OrderRepository, escrowRepo *repository.EscrowRepository, auditRepo *repository.AuditLogRepository, disputeRepo *repository.DisputeRepository, kycRepo *repository.KYCRepository, cfg *config.Config, notification *NotificationService, compliance *ComplianceService) *OrderService {
	return &OrderService{orderRepo: orderRepo, escrowRepo: escrowRepo, auditRepo: auditRepo, disputeRepo: disputeRepo, kycRepo: kycRepo, cfg: cfg, notification: notification, compliance: compliance}
}

func (s *OrderService) notify(ctx context.Context, userID, title, body, notifType string, refID *string) {
	_ = s.notification.Send(ctx, userID, title, body, notifType, refID)
}

// audit — records an escrow lifecycle event for the "Escrow History" audit trail on an
// order. actorID is "" for system/cron-triggered actions.
func (s *OrderService) audit(ctx context.Context, actorID, action, orderID string, metadata map[string]interface{}) {
	_ = s.auditRepo.Record(ctx, actorID, action, "escrow", orderID, metadata)
}

func (s *OrderService) requireKYCVerified(ctx context.Context, userID string) error {
	kyc, err := s.kycRepo.GetByUserID(ctx, userID)
	if err != nil {
		return fmt.Errorf("checking KYC status: %w", err)
	}
	if kyc == nil || kyc.Status != models.KYCVerified {
		return fmt.Errorf("KYC approval required before placing or receiving orders")
	}
	return nil
}

type CreateOrderInput struct {
	ImporterID      string
	ExporterID      string
	ProductName     string
	HSNCode         *string
	Quantity        float64
	Unit            string
	UnitPrice       float64
	DeliveryAddress *string
	Notes           *string
}

// CreateOrder: importer initiates a deal. Order + escrow row created together (status = created).
// Returns a upi://pay deep link — tapping it opens whatever UPI app is installed
// (GPay/PhonePe/Paytm/BHIM/...) with the amount and payee pre-filled. There is no gateway
// callback: the importer pays inside their UPI app, comes back, and taps "Payment Done"
// (see ConfirmPaymentDone) to self-declare it — no cryptographic proof of payment.
// BUG FIX (Journey 2 — KYC gate): CreateOrder previously had no KYC check at all, so an
// unverified importer could place real escrow-backed orders. Both importer and exporter on the
// order must have an approved (verified) KYC before an order can be created.
func (s *OrderService) CreateOrder(ctx context.Context, in CreateOrderInput) (*models.Order, *models.EscrowPayment, string, error) {
	if err := s.requireKYCVerified(ctx, in.ImporterID); err != nil {
		return nil, nil, "", err
	}
	if err := s.requireKYCVerified(ctx, in.ExporterID); err != nil {
		return nil, nil, "", err
	}

	total := in.Quantity * in.UnitPrice
	feePercent := s.cfg.PlatformFeePercent
	feeAmount := round2(total * feePercent / 100)
	payoutAmount := round2(total - feeAmount)

	order := &models.Order{
		OrderNumber:          generateOrderNumber(),
		ImporterID:           in.ImporterID,
		ExporterID:           in.ExporterID,
		ProductName:          in.ProductName,
		HSNCode:              in.HSNCode,
		Quantity:             in.Quantity,
		Unit:                 in.Unit,
		UnitPrice:            in.UnitPrice,
		Currency:             "INR",
		TotalAmount:          total,
		PlatformFeePercent:   feePercent,
		PlatformFeeAmount:    feeAmount,
		ExporterPayoutAmount: payoutAmount,
		Status:               models.OrderCreated,
		AutoReleaseDays:      s.cfg.AutoReleaseDays,
		DeliveryAddress:      in.DeliveryAddress,
		Notes:                in.Notes,
	}

	escrow := &models.EscrowPayment{
		Amount:       total,
		PlatformFee:  feeAmount,
		PayoutAmount: payoutAmount,
		Status:       models.PaymentCreated,
	}

	if err := s.orderRepo.CreateOrderWithEscrow(ctx, order, escrow); err != nil {
		return nil, nil, "", fmt.Errorf("create order: %w", err)
	}

	upiLink := upi.BuildPaymentLink(s.cfg.PlatformUPIVPA, s.cfg.PlatformUPIPayeeName, total, order.OrderNumber, "Escrow payment for "+order.OrderNumber)
	if err := s.escrowRepo.SetRazorpayOrder(ctx, escrow.ID, order.OrderNumber); err != nil {
		return order, escrow, "", fmt.Errorf("saving payment reference: %w", err)
	}
	escrow.RazorpayOrderID = &order.OrderNumber

	s.notify(ctx, order.ImporterID, "Order Created", fmt.Sprintf("Order %s created for %s — complete payment to move it to escrow.", order.OrderNumber, order.ProductName), "order_update", &order.ID)
	s.notify(ctx, order.ExporterID, "Order Created", fmt.Sprintf("Order %s created for %s. Awaiting importer payment.", order.OrderNumber, order.ProductName), "order_update", &order.ID)
	_ = s.notification.NotifyAdmin(ctx, "New Order Created", fmt.Sprintf("Order %s created (%s, ₹%.2f).", order.OrderNumber, order.ProductName, order.TotalAmount), "order_update", &order.ID)

	// Compliance Center — additive, best-effort. Generating the checklist is intentionally
	// never allowed to fail or delay order creation itself: it runs in the background and
	// only logs on error, since compliance is a separate concern layered on top of an order
	// that must exist first regardless of whether a checklist could be generated for it.
	if s.compliance != nil {
		go func(orderID string) {
			if err := s.compliance.GenerateChecklist(context.Background(), orderID); err != nil {
				log.Printf("compliance: could not generate checklist for order %s: %v", orderID, err)
			}
		}(order.ID)
	}

	return order, escrow, upiLink, nil
}

// ListMyOrders — role determines whether we filter by importer_id or exporter_id.
func (s *OrderService) ListMyOrders(ctx context.Context, userID, role string, status *string) ([]models.Order, error) {
	orders, err := s.orderRepo.ListByUser(ctx, userID, models.UserRole(role), status, 50, 0)
	if err != nil {
		return nil, fmt.Errorf("list orders: %w", err)
	}
	return orders, nil
}

// GetEscrowStatus — trimmed escrow view for the order's own importer/exporter (Order
// Details screen), so they can see "Awaiting Buyer Confirmation — Auto Release Due In
// X Days" without hitting the admin-only escrow endpoints.
func (s *OrderService) GetEscrowStatus(ctx context.Context, orderID, requesterID string) (*models.EscrowPayment, error) {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if requesterID != order.ImporterID && requesterID != order.ExporterID {
		return nil, fmt.Errorf("not authorized to view this order's escrow status")
	}
	return s.escrowRepo.GetByOrderID(ctx, orderID)
}

// ConfirmPaymentDone — the importer self-declares "I've paid via UPI" after returning from
// their UPI app. Unlike the old Razorpay flow there's no signature to verify; this is a
// trust-based confirmation by design (see pkg/upi doc comment for the tradeoff).
func (s *OrderService) ConfirmPaymentDone(ctx context.Context, orderID, importerID string) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}
	if order.ImporterID != importerID {
		return fmt.Errorf("not authorized: this order does not belong to you")
	}
	if order.Status != models.OrderCreated {
		return fmt.Errorf("cannot confirm payment: order status is %s", order.Status)
	}

	if err := s.escrowRepo.MarkHeld(ctx, order.ID, "UPI-SELF-CONFIRMED", order.AutoReleaseDays); err != nil {
		return err
	}
	s.audit(ctx, importerID, "escrow.payment_received", order.ID, map[string]interface{}{"amount": order.TotalAmount})

	s.notify(ctx, order.ExporterID, "New Order Received", fmt.Sprintf("Payment for order %s marked as paid by the importer. Prepare the shipment.", order.OrderNumber), "order_update", &order.ID)
	s.notify(ctx, order.ImporterID, "Escrow Locked", fmt.Sprintf("Your payment for order %s is recorded and held in escrow.", order.OrderNumber), "payment", &order.ID)
	_ = s.notification.NotifyAdmin(ctx, "New Escrow", fmt.Sprintf("₹%.2f collected and held in escrow for order %s.", order.TotalAmount, order.OrderNumber), "escrow", &order.ID)
	return nil
}

// ConfirmDeliveryAndRelease: importer confirms goods received, or admin releases directly
// (see AdminService.ReleasePayment / DisputeService.Resolve's "release" path). actorID is
// the user who triggered this — used only for the audit trail (empty string is fine for
// system-triggered calls, though the auto-release cron no longer calls this — see
// cron/auto_release.go, which notifies admin instead of auto-releasing).
// requireOwnership is true for the importer-initiated confirm-delivery endpoint (actorID must be
// the order's own importer, and an open dispute blocks release) and false when called from
// DisputeService.Resolve, where the admin resolving the dispute IS the authority for release and
// the dispute row is still 'open' in the DB at this exact point in that flow.
func (s *OrderService) ConfirmDeliveryAndRelease(ctx context.Context, orderID, actorID string, requireOwnership bool) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}

	// BUG FIX (C1/C2): previously any authenticated importer could release escrow on ANY order by
	// supplying its orderID, not just their own orders — no ownership check existed. Also added a
	// check blocking self-initiated release while an open dispute exists on the order.
	if requireOwnership {
		if actorID != order.ImporterID {
			return fmt.Errorf("not authorized: this order does not belong to you")
		}
		if openDispute, derr := s.disputeRepo.GetOpenByOrderID(ctx, orderID); derr == nil && openDispute != nil {
			return fmt.Errorf("cannot release: this order has an open dispute pending resolution")
		}
	}

	escrow, err := s.escrowRepo.GetByOrderID(ctx, orderID)
	if err != nil {
		return err
	}
	if escrow.Status != models.PaymentHeld && escrow.Status != models.PaymentOnHold {
		return fmt.Errorf("cannot release: payment status is %s, expected held or on_hold", escrow.Status)
	}

	payoutRef := fmt.Sprintf("MANUAL-PENDING-%d", time.Now().Unix())
	if err := s.escrowRepo.MarkReleased(ctx, orderID, order.ExporterID, payoutRef); err != nil {
		return err
	}
	s.audit(ctx, actorID, "escrow.released", order.ID, map[string]interface{}{"payout_amount": escrow.PayoutAmount})

	s.notify(ctx, order.ExporterID, "Payment Released", fmt.Sprintf("₹%.2f approved for payout on order %s. Platform will transfer it to your account.", escrow.PayoutAmount, order.OrderNumber), "payment", &order.ID)
	s.notify(ctx, order.ExporterID, "Wallet Credited", fmt.Sprintf("₹%.2f has been credited to your wallet for order %s.", escrow.PayoutAmount, order.OrderNumber), "wallet", &order.ID)
	s.notify(ctx, order.ImporterID, "Delivery Confirmed", fmt.Sprintf("Order %s marked complete — payment released to the exporter.", order.OrderNumber), "order_update", &order.ID)
	return nil
}

// HoldPayment — admin pauses a held escrow payment (e.g. pending investigation). Blocks
// the auto-release cron until admin either releases or refunds it.
func (s *OrderService) HoldPayment(ctx context.Context, orderID, adminID string) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}
	if err := s.escrowRepo.MarkOnHold(ctx, orderID); err != nil {
		return fmt.Errorf("hold payment: %w", err)
	}
	s.audit(ctx, adminID, "escrow.hold", order.ID, nil)

	s.notify(ctx, order.ExporterID, "Payment Under Review", fmt.Sprintf("Payment for order %s has been placed on hold by the platform for review.", order.OrderNumber), "payment", &order.ID)
	s.notify(ctx, order.ImporterID, "Payment Under Review", fmt.Sprintf("Payment for order %s has been placed on hold by the platform for review.", order.OrderNumber), "payment", &order.ID)
	return nil
}

// RefundPayment — admin directly refunds a held/on-hold escrow payment without requiring
// a dispute to exist first (DisputeService.Resolve covers the dispute-driven refund path;
// this is the direct one, e.g. order cancelled before shipment).
//
// BUG FIX (Journey 7): previously had no open-dispute check at all, so an admin could refund
// an order with an open dispute through this direct action, moving money while completely
// bypassing DisputeService.Resolve — the dispute itself would stay 'open' forever even though
// the money had already moved. Now requires going through dispute resolution instead, which
// both moves the money AND closes the dispute in one step.
func (s *OrderService) RefundPayment(ctx context.Context, orderID, adminID, reason string) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}
	if openDispute, derr := s.disputeRepo.GetOpenByOrderID(ctx, orderID); derr == nil && openDispute != nil {
		return fmt.Errorf("cannot refund directly: order has an open dispute — resolve it via the Disputes screen instead")
	}
	if err := s.escrowRepo.MarkRefunded(ctx, orderID, order.ImporterID); err != nil {
		return fmt.Errorf("refund payment: %w", err)
	}
	s.audit(ctx, adminID, "escrow.refunded", order.ID, map[string]interface{}{"reason": reason})

	s.notify(ctx, order.ImporterID, "Payment Refunded", fmt.Sprintf("Your payment for order %s has been refunded: %s", order.OrderNumber, reason), "payment", &order.ID)
	s.notify(ctx, order.ExporterID, "Order Refunded", fmt.Sprintf("Order %s was refunded to the importer: %s", order.OrderNumber, reason), "payment", &order.ID)
	return nil
}

// NotifyPendingRelease — called by the auto-release cron once the escrow's release_due_at
// has passed with no dispute raised. Notifies admin (who must now manually release/hold/
// refund via the Admin Escrow screen) and reminds the importer to confirm delivery — this
// replaces the old behavior of auto-releasing on schedule.
func (s *OrderService) NotifyPendingRelease(ctx context.Context, order *models.Order) {
	s.notify(ctx, order.ImporterID, "Confirm Delivery Reminder", fmt.Sprintf("Order %s is awaiting your delivery confirmation. Please confirm receipt or report an issue — this has now been flagged for admin review.", order.OrderNumber), "order_update", &order.ID)
	_ = s.notification.NotifyAdmin(ctx, "Pending Release", fmt.Sprintf("Order %s: auto-release window has passed with no dispute. Review and release/hold/refund from Escrow Payments.", order.OrderNumber), "escrow", &order.ID)
}

func round2(f float64) float64 {
	return float64(int(f*100+0.5)) / 100
}

func generateOrderNumber() string {
	year := time.Now().Year()
	// Production mein ye ek DB sequence honi chahiye taaki collision-proof ho.
	// Abhi ke liye random suffix — TODO: replace with sequence before go-live.
	return fmt.Sprintf("OBEI-%d-%06d", year, rand.Intn(999999))
}
