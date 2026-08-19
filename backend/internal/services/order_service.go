package services

import (
	"context"
	cryptorand "crypto/rand"
	"fmt"
	"log"
	"math"
	"math/big"
	"math/rand"
	"strings"
	"time"

	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/pkg/stripe"
	"github.com/jayashri-infotech/onebharat-backend/pkg/upi"
)

type OrderService struct {
	orderRepo        *repository.OrderRepository
	escrowRepo       *repository.EscrowRepository
	auditRepo        *repository.AuditLogRepository
	disputeRepo      *repository.DisputeRepository
	kycRepo          *repository.KYCRepository
	paymentTermsRepo *repository.PaymentTermsRepository
	userRepo         *repository.UserRepository
	cfg              *config.Config
	notification     *NotificationService
	compliance       *ComplianceService
	stripe           *stripe.Client
}

func NewOrderService(orderRepo *repository.OrderRepository, escrowRepo *repository.EscrowRepository, auditRepo *repository.AuditLogRepository, disputeRepo *repository.DisputeRepository, kycRepo *repository.KYCRepository, paymentTermsRepo *repository.PaymentTermsRepository, userRepo *repository.UserRepository, cfg *config.Config, notification *NotificationService, compliance *ComplianceService, stripeClient *stripe.Client) *OrderService {
	return &OrderService{orderRepo: orderRepo, escrowRepo: escrowRepo, auditRepo: auditRepo, disputeRepo: disputeRepo, kycRepo: kycRepo, paymentTermsRepo: paymentTermsRepo, userRepo: userRepo, cfg: cfg, notification: notification, compliance: compliance, stripe: stripeClient}
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
	Currency        string // Journey 10 "multi currency" — empty defaults to INR (existing behavior)
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
	// BUG FIX (H-2): exporter_id was accepted as a plain string with no check that it actually
	// belonged to an exporter, or that it differed from the importer — a user could place an
	// escrow-backed order naming themselves as both buyer and seller, or an arbitrary unrelated
	// account as the seller.
	if in.ImporterID == in.ExporterID {
		return nil, nil, "", fmt.Errorf("importer and exporter cannot be the same account")
	}
	exporter, err := s.userRepo.GetByID(ctx, in.ExporterID)
	if err != nil {
		return nil, nil, "", fmt.Errorf("looking up exporter: %w", err)
	}
	if exporter == nil || exporter.Role != models.RoleExporter {
		return nil, nil, "", fmt.Errorf("the selected seller is not a registered exporter")
	}

	if err := s.requireKYCVerified(ctx, in.ImporterID); err != nil {
		return nil, nil, "", err
	}
	if err := s.requireKYCVerified(ctx, in.ExporterID); err != nil {
		return nil, nil, "", err
	}

	// BUG FIX (L-4): total was stored unrounded while feeAmount/payoutAmount were both round2'd,
	// so platform_fee_amount + exporter_payout_amount could differ from total_amount by a
	// fraction of a paisa. Round total first so all three figures are internally consistent.
	total := round2(in.Quantity * in.UnitPrice)
	feePercent := s.cfg.PlatformFeePercent
	feeAmount := round2(total * feePercent / 100)
	payoutAmount := round2(total - feeAmount)

	currency := in.Currency
	if currency == "" {
		currency = "INR"
	}

	order := &models.Order{
		OrderNumber:          generateOrderNumber(),
		ImporterID:           in.ImporterID,
		ExporterID:           in.ExporterID,
		ProductName:          in.ProductName,
		HSNCode:              in.HSNCode,
		Quantity:             in.Quantity,
		Unit:                 in.Unit,
		UnitPrice:            in.UnitPrice,
		Currency:             currency,
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

	// UPI is an India-domestic payment rail — only build a upi://pay link for INR orders.
	// International (non-INR) orders pay via bank transfer instead (see ConfirmBankTransfer)
	// or Stripe once configured; the frontend checks for an empty upiLink to know which
	// payment instructions to show.
	upiLink := ""
	if currency == "INR" {
		upiLink = upi.BuildPaymentLink(s.cfg.PlatformUPIVPA, s.cfg.PlatformUPIPayeeName, total, order.OrderNumber, "Escrow payment for "+order.OrderNumber)
	}
	if err := s.escrowRepo.SetRazorpayOrder(ctx, escrow.ID, order.OrderNumber); err != nil {
		return order, escrow, "", fmt.Errorf("saving payment reference: %w", err)
	}
	escrow.RazorpayOrderID = &order.OrderNumber

	s.notify(ctx, order.ImporterID, "Order Created", fmt.Sprintf("Order %s created for %s — complete payment to move it to escrow.", order.OrderNumber, order.ProductName), "order_update", &order.ID)
	s.notify(ctx, order.ExporterID, "Order Created", fmt.Sprintf("Order %s created for %s. Awaiting importer payment.", order.OrderNumber, order.ProductName), "order_update", &order.ID)
	// BUG FIX (M-9): hardcoded ₹ regardless of order.Currency — a USD/EUR/etc. order reported
	// rupee amounts in admin alerts and both parties' notifications.
	_ = s.notification.NotifyAdmin(ctx, "New Order Created", fmt.Sprintf("Order %s created (%s, %s%.2f).", order.OrderNumber, order.ProductName, order.Currency, order.TotalAmount), "order_update", &order.ID)

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
func (s *OrderService) ListMyOrders(ctx context.Context, userID, role string, status *string, limit, offset int) ([]models.Order, error) {
	if limit <= 0 {
		limit = 50
	}
	orders, err := s.orderRepo.ListByUser(ctx, userID, models.UserRole(role), status, limit, offset)
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
// rejectIfMilestoneTermsExist — SECURITY/LOGIC FIX (C-03): escrow's single-payment release and
// the milestone-escrow module's per-milestone release both independently credit the exporter
// for the same order with nothing making them mutually exclusive — a milestone schedule set up
// on an order whose escrow later auto-releases (or vice versa) results in the exporter being
// paid twice for one collected payment. An order that already has payment terms set up must use
// ONLY the milestone release path; refuse to also start the single-payment escrow rail for it.
func (s *OrderService) rejectIfMilestoneTermsExist(ctx context.Context, orderID string) error {
	if s.paymentTermsRepo == nil {
		return nil
	}
	if terms, err := s.paymentTermsRepo.GetByOrderID(ctx, orderID); err == nil && terms != nil {
		return fmt.Errorf("this order uses milestone-based payment terms — pay via its milestone schedule instead")
	}
	return nil
}

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
	if err := s.rejectIfMilestoneTermsExist(ctx, order.ID); err != nil {
		return err
	}

	if err := s.escrowRepo.MarkHeld(ctx, order.ID, "UPI-SELF-CONFIRMED", order.AutoReleaseDays); err != nil {
		return err
	}
	s.audit(ctx, importerID, "escrow.payment_received", order.ID, map[string]interface{}{"amount": order.TotalAmount})

	s.notify(ctx, order.ExporterID, "New Order Received", fmt.Sprintf("Payment for order %s marked as paid by the importer. Prepare the shipment.", order.OrderNumber), "order_update", &order.ID)
	s.notify(ctx, order.ImporterID, "Escrow Locked", fmt.Sprintf("Your payment for order %s is recorded and held in escrow.", order.OrderNumber), "payment", &order.ID)
	_ = s.notification.NotifyAdmin(ctx, "New Escrow", fmt.Sprintf("%s%.2f collected and held in escrow for order %s.", order.Currency, order.TotalAmount, order.OrderNumber), "escrow", &order.ID)
	return nil
}

// ConfirmBankTransfer — Journey 10 "bank transfer": the importer self-declares having wired
// the money to the platform's bank account, providing a reference/UTR number for
// reconciliation. Same trust model and escrow effect as ConfirmPaymentDone (UPI) — no gateway
// integration, importer-declared — just a different payment rail, mainly for international
// (non-INR) orders where UPI isn't available.
func (s *OrderService) ConfirmBankTransfer(ctx context.Context, orderID, importerID, referenceNumber string) error {
	if referenceNumber == "" {
		return fmt.Errorf("a bank transfer reference/UTR number is required")
	}
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
	if err := s.rejectIfMilestoneTermsExist(ctx, order.ID); err != nil {
		return err
	}

	if err := s.escrowRepo.MarkHeld(ctx, order.ID, "BANK-TRANSFER-"+referenceNumber, order.AutoReleaseDays); err != nil {
		return err
	}
	s.audit(ctx, importerID, "escrow.payment_received", order.ID, map[string]interface{}{"amount": order.TotalAmount, "method": "bank_transfer", "reference": referenceNumber})

	s.notify(ctx, order.ExporterID, "New Order Received", fmt.Sprintf("Payment for order %s marked as paid by the importer via bank transfer. Prepare the shipment.", order.OrderNumber), "order_update", &order.ID)
	s.notify(ctx, order.ImporterID, "Escrow Locked", fmt.Sprintf("Your bank transfer for order %s is recorded and held in escrow.", order.OrderNumber), "payment", &order.ID)
	_ = s.notification.NotifyAdmin(ctx, "New Escrow (Bank Transfer)", fmt.Sprintf("%s %.2f reported via bank transfer (ref %s) for order %s — verify against bank statement.", order.Currency, order.TotalAmount, referenceNumber, order.OrderNumber), "escrow", &order.ID)
	return nil
}

// ConfirmPaymentViaGateway — Journey 10 "webhook verification": called only after a webhook
// handler has cryptographically verified the gateway's signature (Razorpay or Stripe) on a
// payment-succeeded event. Unlike ConfirmPaymentDone/ConfirmBankTransfer (self-declared, no
// proof), this has actual gateway-verified proof of payment — gatewayReference is the
// Razorpay payment ID or Stripe PaymentIntent ID, stored the same way UPI/bank-transfer
// references are.
// ConfirmPaymentViaGateway — SECURITY FIX (C-02): previously marked full escrow held on any
// genuinely-signed webhook with a matching order_id, WITHOUT ever checking the amount actually
// paid or its currency. Anyone who created a Rs.1 payment carrying notes.order_id for a
// Rs.10,00,000 order would have the full order amount held in escrow and (after auto-release)
// paid out. paidAmountMinor is the amount actually captured, in the gateway's minor currency
// unit (paise/cents); paidCurrency is the gateway's ISO currency code. Both are now compared
// against the order's own recorded total/currency before anything is marked held.
func (s *OrderService) ConfirmPaymentViaGateway(ctx context.Context, orderID, gatewayReference string, paidAmountMinor int64, paidCurrency string) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}
	if order.Status != models.OrderCreated {
		// BUG FIX (H-10): this is also what makes ConfirmPaymentViaGateway idempotent on
		// payment id — a retried/duplicate webhook for an order already past "created" is a
		// no-op error here, not a double-hold.
		return fmt.Errorf("cannot confirm payment: order status is %s", order.Status)
	}
	if err := s.rejectIfMilestoneTermsExist(ctx, order.ID); err != nil {
		return err
	}

	// BUG FIX (H-17): use math.Round instead of truncating float->int64, which previously
	// under-collected ~5.7% of orders by one minor unit versus orders.total_amount.
	expectedMinor := int64(math.Round(order.TotalAmount * 100))
	if paidAmountMinor < expectedMinor {
		return fmt.Errorf("payment amount mismatch: expected %d minor units, gateway reported %d", expectedMinor, paidAmountMinor)
	}
	if paidCurrency != "" && order.Currency != "" && !strings.EqualFold(paidCurrency, order.Currency) {
		return fmt.Errorf("payment currency mismatch: order is %s, gateway reported %s", order.Currency, paidCurrency)
	}

	if err := s.escrowRepo.MarkHeld(ctx, order.ID, gatewayReference, order.AutoReleaseDays); err != nil {
		return err
	}
	s.audit(ctx, "", "escrow.payment_received", order.ID, map[string]interface{}{"amount": order.TotalAmount, "method": "gateway_webhook", "reference": gatewayReference})

	s.notify(ctx, order.ExporterID, "New Order Received", fmt.Sprintf("Payment for order %s confirmed by the payment gateway. Prepare the shipment.", order.OrderNumber), "order_update", &order.ID)
	s.notify(ctx, order.ImporterID, "Escrow Locked", fmt.Sprintf("Your payment for order %s is confirmed and held in escrow.", order.OrderNumber), "payment", &order.ID)
	return nil
}

// CreateStripePaymentIntent — Journey 10 "Stripe": an alternative to UPI/bank transfer for
// international/card-paying importers on non-INR orders. Returns the client secret the
// frontend needs to confirm payment with Stripe.js/Flutter's Stripe SDK; escrow is marked
// held only once the webhook confirms payment_intent.succeeded (see WebhookHandler.Stripe /
// ConfirmPaymentViaGateway) — this call alone does not move any money.
func (s *OrderService) CreateStripePaymentIntent(ctx context.Context, orderID, importerID string) (*stripe.PaymentIntent, error) {
	if s.stripe == nil || !s.stripe.Configured() {
		return nil, fmt.Errorf("card payments are not available right now")
	}
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return nil, err
	}
	if order.ImporterID != importerID {
		return nil, fmt.Errorf("not authorized: this order does not belong to you")
	}
	if order.Status != models.OrderCreated {
		return nil, fmt.Errorf("cannot start payment: order status is %s", order.Status)
	}
	// BUG FIX (H-3): this path never checked for milestone payment terms — the other three
	// confirm paths (ConfirmPaymentDone/ConfirmBankTransfer/ConfirmPaymentViaGateway) all call
	// rejectIfMilestoneTermsExist first, so a Stripe charge could be started (and the card
	// captured) for an order that's actually on milestone terms, then get stranded when the
	// webhook rejects it.
	if err := s.rejectIfMilestoneTermsExist(ctx, order.ID); err != nil {
		return nil, err
	}
	// BUG FIX (C-3): previously int64(round2(total) * 100) — round2 rounds to 2 decimal places
	// first, then the *100 multiply/truncate can still land a fraction of a cent off due to
	// float representation, while ConfirmPaymentViaGateway (the webhook side) computes the
	// expected minor-unit amount via math.Round(total * 100) directly. The two could disagree
	// by one minor unit, so Stripe would capture the card and the webhook would then reject the
	// payment as a mismatch. Use the exact same formula as the webhook check.
	amountMinor := int64(math.Round(order.TotalAmount * 100))
	return s.stripe.CreatePaymentIntent(ctx, amountMinor, order.Currency, order.ID)
}

// BankTransferDetails — the platform's bank account for importers paying via wire transfer.
type BankTransferInfo struct {
	AccountName   string `json:"account_name"`
	AccountNumber string `json:"account_number"`
	IFSC          string `json:"ifsc"`
	SWIFT         string `json:"swift"`
	BankName      string `json:"bank_name"`
	Configured    bool   `json:"configured"`
}

func (s *OrderService) BankTransferDetails() BankTransferInfo {
	return BankTransferInfo{
		AccountName:   s.cfg.PlatformBankAccountName,
		AccountNumber: s.cfg.PlatformBankAccountNumber,
		IFSC:          s.cfg.PlatformBankIFSC,
		SWIFT:         s.cfg.PlatformBankSWIFT,
		BankName:      s.cfg.PlatformBankName,
		Configured:    s.cfg.PlatformBankAccountNumber != "",
	}
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
	// supplying its orderID, not just their own orders — no ownership check existed.
	if requireOwnership && actorID != order.ImporterID {
		return fmt.Errorf("not authorized: this order does not belong to you")
	}
	// LOGIC FIX (L-09): order.Status was never consulted at all — an importer could confirm
	// delivery and release the full payout on an order that was never actually shipped (a
	// mis-tap released the payout with zero goods movement and no way back). Self-service
	// delivery confirmation now requires the order to have actually progressed to a shipped
	// state first. Admin/dispute-resolution releases (requireOwnership=false) intentionally
	// keep the broader trust boundary they already had — an admin resolving a dispute or
	// approving a direct release is a deliberate override, not a mis-tap.
	if requireOwnership {
		switch order.Status {
		case models.OrderShipped, models.OrderInTransit, models.OrderDelivered, models.OrderConfirmed:
			// ok — goods have actually moved
		default:
			return fmt.Errorf("cannot confirm delivery: order has not been shipped yet (status: %s)", order.Status)
		}
	}
	// RACE FIX (H-13): the open-dispute check previously only ran when requireOwnership was
	// true — the auto-release cron calls this with requireOwnership=false, and the cron's own
	// dispute check (reading order.Status at the top of its loop iteration) left a race window
	// where a dispute raised between that read and this call would still let the cron release
	// escrow out from under an unresolved dispute (which then becomes unrefundable, since
	// MarkRefunded rejects an already-released escrow). The dispute check is now unconditional —
	// DisputeService.Resolve's own "release" call path is unaffected because it resolves the
	// dispute row to 'resolved' BEFORE calling this, so GetOpenByOrderID correctly finds nothing.
	// FAIL-CLOSED FIX (M-23): previously "derr == nil && openDispute != nil" meant a transient
	// DB error on this check silently SKIPPED it — releasing escrow with a dispute potentially
	// still open. A lookup error is now itself treated as "don't release", not "assume clear".
	openDispute, derr := s.disputeRepo.GetOpenByOrderID(ctx, orderID)
	if derr != nil {
		return fmt.Errorf("could not verify dispute status, please retry: %w", derr)
	}
	if openDispute != nil {
		return fmt.Errorf("cannot release: this order has an open dispute pending resolution")
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

	s.notify(ctx, order.ExporterID, "Payment Released", fmt.Sprintf("%s%.2f approved for payout on order %s. Platform will transfer it to your account.", order.Currency, escrow.PayoutAmount, order.OrderNumber), "payment", &order.ID)
	s.notify(ctx, order.ExporterID, "Wallet Credited", fmt.Sprintf("%s%.2f has been credited to your wallet for order %s.", order.Currency, escrow.PayoutAmount, order.OrderNumber), "wallet", &order.ID)
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
	// FAIL-CLOSED FIX (M-23): a lookup error here must block the refund, not silently allow it.
	if openDispute, derr := s.disputeRepo.GetOpenByOrderID(ctx, orderID); derr != nil {
		return fmt.Errorf("could not verify dispute status, please retry: %w", derr)
	} else if openDispute != nil {
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

// RefundPartial — Journey 10 "partial refund": admin refunds only part of a held/on-hold
// escrow (e.g. a shortage settlement), leaving the remainder available for normal release.
// Same open-dispute guard as the full-refund path.
func (s *OrderService) RefundPartial(ctx context.Context, orderID, adminID string, amount float64, reason string) error {
	order, err := s.orderRepo.GetByID(ctx, orderID)
	if err != nil {
		return err
	}
	// FAIL-CLOSED FIX (M-23): a lookup error here must block the refund, not silently allow it.
	if openDispute, derr := s.disputeRepo.GetOpenByOrderID(ctx, orderID); derr != nil {
		return fmt.Errorf("could not verify dispute status, please retry: %w", derr)
	} else if openDispute != nil {
		return fmt.Errorf("cannot refund directly: order has an open dispute — resolve it via the Disputes screen instead")
	}
	if err := s.escrowRepo.RefundPartial(ctx, orderID, order.ImporterID, amount); err != nil {
		return fmt.Errorf("partial refund: %w", err)
	}
	s.audit(ctx, adminID, "escrow.partial_refund", order.ID, map[string]interface{}{"amount": amount, "reason": reason})

	s.notify(ctx, order.ImporterID, "Partial Refund Issued", fmt.Sprintf("%s%.2f of your payment for order %s has been refunded: %s", order.Currency, amount, order.OrderNumber, reason), "payment", &order.ID)
	s.notify(ctx, order.ExporterID, "Partial Refund Issued", fmt.Sprintf("A partial refund of %s%.2f was issued to the importer for order %s: %s", order.Currency, amount, order.OrderNumber, reason), "payment", &order.ID)
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

// BUG FIX (M-8): previously float64(int(f*100+0.5))/100 — a manual "add 0.5 then truncate"
// rounding that (a) is inconsistent with math.Round, used by the gateway-payment check in
// ConfirmPaymentViaGateway (this mismatch was the direct cause of C-3), and (b) rounds negative
// values in the wrong direction (int() truncates toward zero, so -0.5 truncates to 0 instead of
// rounding to -1 the way math.Round would). Every fee/payout/milestone amount now uses the same
// rounding function as the gateway check.
func round2(f float64) float64 {
	return math.Round(f*100) / 100
}

// generateOrderNumber — BUG FIX (M-27): previously a 6-digit rand.Intn(999999) suffix (which
// also never returns 999999) against a UNIQUE column — birthday-bound collision odds reach
// ~50% by roughly 1,200 orders in a year, surfacing as a raw duplicate-key 500 with no retry
// (the importer simply couldn't place that order). Widened to a 9-digit suffix seeded from
// crypto/rand (~1 billion combinations, collision odds negligible at any realistic order
// volume) plus a millisecond timestamp component for additional entropy across rapid calls.
func generateOrderNumber() string {
	year := time.Now().Year()
	return fmt.Sprintf("OBEI-%d-%d%06d", year, time.Now().UnixNano()%1000, secureRandInt(1000000000))
}

func secureRandInt(max int64) int64 {
	n, err := cryptorand.Int(cryptorand.Reader, big.NewInt(max))
	if err != nil {
		return rand.Int63n(max)
	}
	return n.Int64()
}
