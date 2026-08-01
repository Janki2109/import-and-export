// Package payment defines the provider-agnostic interface a future payment integration would
// implement. NOT WIRED into any handler/service/route today — the platform's real payment
// flow is still the existing self-declared UPI + escrow system (see services/order_service.go),
// which this package does not touch or replace.
//
// This exists so that adding a real gateway (Stripe, Razorpay, Airwallex, Adyen, Wise) later
// is "implement this interface + wire one constructor in main.go" rather than a redesign.
// See docs/SECURITY_ARCHITECTURE.md for the integration plan and why this isn't live yet
// (needs real merchant credentials + a decision on which gateway to launch with).
package payment

import "context"

type PaymentStatus string

const (
	StatusPending    PaymentStatus = "pending"
	StatusAuthorized PaymentStatus = "authorized"
	StatusCaptured   PaymentStatus = "captured"
	StatusFailed     PaymentStatus = "failed"
	StatusRefunded   PaymentStatus = "refunded"
)

// ChargeRequest — deliberately has no card/bank fields. A real implementation exchanges a
// client-side payment-method token (from Stripe.js / Razorpay Checkout / etc.) for a charge —
// raw card numbers/CVVs must never reach this backend (Part 5's "do not store card data").
type ChargeRequest struct {
	OrderID            string
	AmountMinor        int64 // smallest currency unit (e.g. paise, cents) — never a float, to avoid rounding bugs
	Currency           string
	PaymentMethodToken string // opaque token from the provider's client-side SDK
	IdempotencyKey     string
}

type ChargeResult struct {
	ProviderReference string // the gateway's own transaction/charge id — this is what gets audit-logged
	Status            PaymentStatus
}

// Provider is what every gateway integration implements. Milestone release / escrow logic
// stays in services.OrderService / PaymentTermsService exactly as it is today — a Provider
// only ever executes a single charge or refund; it has no opinion about escrow/milestones.
type Provider interface {
	Name() string
	Charge(ctx context.Context, req ChargeRequest) (*ChargeResult, error)
	Refund(ctx context.Context, providerReference string, amountMinor int64) (*ChargeResult, error)
	VerifyWebhookSignature(payload []byte, signatureHeader string) bool
}

// Registry lets the platform support multiple concurrent gateways (Part 5's "architecture
// should support future payment providers") — e.g. Razorpay for India-based accounts, Stripe
// for everyone else — selected per-order rather than a single global provider.
type Registry struct {
	providers map[string]Provider
}

func NewRegistry() *Registry { return &Registry{providers: map[string]Provider{}} }

func (r *Registry) Register(p Provider) { r.providers[p.Name()] = p }

func (r *Registry) Get(name string) (Provider, bool) {
	p, ok := r.providers[name]
	return p, ok
}
