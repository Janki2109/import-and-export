package handlers

import (
	"encoding/json"
	"io"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/config"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/razorpay"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
	"github.com/jayashri-infotech/onebharat-backend/pkg/stripe"
)

// WebhookHandler — Journey 10 "webhook verification". Unauthenticated by JWT (webhooks come
// from the gateway, not a logged-in user) — trust is established entirely by verifying the
// gateway's cryptographic signature over the raw request body before acting on anything in it.
type WebhookHandler struct {
	cfg          *config.Config
	orderService *services.OrderService
}

func NewWebhookHandler(cfg *config.Config, orderService *services.OrderService) *WebhookHandler {
	return &WebhookHandler{cfg: cfg, orderService: orderService}
}

// Razorpay — POST /webhooks/razorpay. Configure this URL + RAZORPAY_WEBHOOK_SECRET in the
// Razorpay dashboard. Verifies X-Razorpay-Signature before parsing/acting on the payload.
func (h *WebhookHandler) Razorpay(c *gin.Context) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "could not read request body")
		return
	}
	signature := c.GetHeader("X-Razorpay-Signature")
	if !razorpay.VerifyWebhookSignature(body, signature, h.cfg.RazorpayWebhookSecret) {
		response.Error(c, http.StatusUnauthorized, "invalid webhook signature")
		return
	}

	var event struct {
		Event   string `json:"event"`
		Payload struct {
			Payment struct {
				Entity struct {
					ID       string            `json:"id"`
					Amount   int64             `json:"amount"`   // paise, per Razorpay's documented payload shape
					Currency string            `json:"currency"` // e.g. "INR"
					Notes    map[string]string `json:"notes"`
				} `json:"entity"`
			} `json:"payment"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(body, &event); err != nil {
		response.Error(c, http.StatusBadRequest, "malformed webhook payload")
		return
	}

	// Signature is verified at this point — the payload can now be trusted. "payment.captured"
	// is the event that would confirm a real Razorpay Checkout payment (once that flow exists
	// alongside today's self-declared UPI/bank-transfer paths); notes.order_id is expected to
	// carry our own order ID, set at Razorpay Order creation time.
	if event.Event == "payment.captured" {
		orderID := event.Payload.Payment.Entity.Notes["order_id"]
		if orderID == "" {
			log.Printf("razorpay webhook: payment.captured with no order_id in notes, payment %s", event.Payload.Payment.Entity.ID)
		} else if err := h.orderService.ConfirmPaymentViaGateway(c.Request.Context(), orderID, event.Payload.Payment.Entity.ID, event.Payload.Payment.Entity.Amount, event.Payload.Payment.Entity.Currency); err != nil {
			log.Printf("razorpay webhook: could not confirm payment for order %s: %v", orderID, err)
			// BUG FIX (H-10): previously always answered 200 even when confirmation failed, so
			// Razorpay marked the webhook delivered and never retried a transient failure (DB
			// blip etc). A genuine amount/currency mismatch (fraud attempt) is NOT worth a
			// retry — respond 200 so the gateway stops resending it — but any other failure
			// (order lookup, DB write) should get a 5xx so the gateway retries until it lands.
			if isPaymentMismatch(err) {
				response.Success(c, http.StatusOK, gin.H{"received": true})
				return
			}
			response.Error(c, http.StatusInternalServerError, "could not process webhook, please retry")
			return
		}
	}

	response.Success(c, http.StatusOK, gin.H{"received": true})
}

// isPaymentMismatch distinguishes a deliberate/fraudulent amount-or-currency mismatch (never
// worth retrying — the gateway resending the same short payment will never succeed) from a
// transient processing failure (worth a 5xx so the gateway retries).
func isPaymentMismatch(err error) bool {
	msg := err.Error()
	return len(msg) >= 15 && (msg[:15] == "payment amount " || (len(msg) >= 17 && msg[:17] == "payment currency"))
}

// Stripe — POST /webhooks/stripe. Verifies the Stripe-Signature header before acting.
func (h *WebhookHandler) Stripe(c *gin.Context) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "could not read request body")
		return
	}
	signature := c.GetHeader("Stripe-Signature")
	if !stripe.VerifyWebhookSignature(body, signature, h.cfg.StripeWebhookSecret) {
		response.Error(c, http.StatusUnauthorized, "invalid webhook signature")
		return
	}

	var event struct {
		Type string `json:"type"`
		Data struct {
			Object struct {
				ID       string            `json:"id"`
				Amount   int64             `json:"amount"`   // minor units (cents), per Stripe's documented payload shape
				Currency string            `json:"currency"` // e.g. "usd"
				Metadata map[string]string `json:"metadata"`
			} `json:"object"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &event); err != nil {
		response.Error(c, http.StatusBadRequest, "malformed webhook payload")
		return
	}

	if event.Type == "payment_intent.succeeded" {
		orderID := event.Data.Object.Metadata["order_id"]
		if orderID == "" {
			log.Printf("stripe webhook: payment_intent.succeeded with no order_id metadata, intent %s", event.Data.Object.ID)
		} else if err := h.orderService.ConfirmPaymentViaGateway(c.Request.Context(), orderID, event.Data.Object.ID, event.Data.Object.Amount, event.Data.Object.Currency); err != nil {
			log.Printf("stripe webhook: could not confirm payment for order %s: %v", orderID, err)
			if isPaymentMismatch(err) {
				response.Success(c, http.StatusOK, gin.H{"received": true})
				return
			}
			response.Error(c, http.StatusInternalServerError, "could not process webhook, please retry")
			return
		}
	}

	response.Success(c, http.StatusOK, gin.H{"received": true})
}
