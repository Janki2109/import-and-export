package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type OrderHandler struct {
	orderService *services.OrderService
}

func NewOrderHandler(orderService *services.OrderService) *OrderHandler {
	return &OrderHandler{orderService: orderService}
}

// parseIntQuery — BUG FIX (M-28) helper: parses a pagination query param, falling back to
// `def` if absent/invalid, and capping at `max` (0 = no cap) so callers can't request an
// unbounded page size.
func parseIntQuery(c *gin.Context, key string, def, max int) int {
	v := c.Query(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return def
	}
	if max > 0 && n > max {
		return max
	}
	return n
}

type createOrderRequest struct {
	ExporterID  string  `json:"exporter_id" binding:"required"`
	ProductName string  `json:"product_name" binding:"required"`
	HSNCode     *string `json:"hsn_code"`
	Quantity    float64 `json:"quantity" binding:"required,gt=0"`
	Unit        string  `json:"unit" binding:"required"`
	UnitPrice   float64 `json:"unit_price" binding:"required,gt=0"`
	// Currency — Journey 10 "multi currency"; optional, defaults to INR (existing behavior).
	Currency        *string `json:"currency" binding:"omitempty,len=3"`
	DeliveryAddress *string `json:"delivery_address"`
	Notes           *string `json:"notes"`
}

// CreateOrder — importer only. Returns order + a upi://pay link for Flutter to launch
// the user's UPI app (GPay/PhonePe/etc). No payment gateway involved.
func (h *OrderHandler) CreateOrder(c *gin.Context) {
	importerID := c.GetString("user_id")

	var req createOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	currency := ""
	if req.Currency != nil {
		currency = *req.Currency
	}
	order, escrow, upiLink, err := h.orderService.CreateOrder(c.Request.Context(), services.CreateOrderInput{
		ImporterID:      importerID,
		ExporterID:      req.ExporterID,
		ProductName:     req.ProductName,
		HSNCode:         req.HSNCode,
		Quantity:        req.Quantity,
		Unit:            req.Unit,
		UnitPrice:       req.UnitPrice,
		Currency:        currency,
		DeliveryAddress: req.DeliveryAddress,
		Notes:           req.Notes,
	})
	if err != nil {
		// BUG FIX (L-3): every CreateOrder failure — including ordinary business-rule rejections
		// like "KYC approval required" — was reported as HTTP 500, so a normal validation
		// failure surfaced to the client as a server error instead of the actionable 400 the
		// same message would be as a "Bad Request" (matching how every other handler in this
		// codebase reports a service-layer rejection).
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	response.Success(c, http.StatusCreated, gin.H{
		"order":    order,
		"upi_link": upiLink,
		"amount":   escrow.Amount,
	})
}

// ListMyOrders — returns orders for the logged-in importer or exporter.
func (h *OrderHandler) ListMyOrders(c *gin.Context) {
	userID := c.GetString("user_id")
	role := c.GetString("role")
	status := c.Query("status")

	var statusPtr *string
	if status != "" {
		statusPtr = &status
	}

	// BUG FIX (M-28): pagination was previously hardcoded to LIMIT 50 OFFSET 0 with no way to
	// page — an importer/exporter with more than 50 orders had their oldest ones (including any
	// open escrow on them) permanently invisible. limit/offset are now accepted as query params.
	limit := parseIntQuery(c, "limit", 50, 200)
	offset := parseIntQuery(c, "offset", 0, 0)

	orders, err := h.orderService.ListMyOrders(c.Request.Context(), userID, role, statusPtr, limit, offset)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, orders)
}

type confirmPaymentRequest struct {
	OrderID string `json:"order_id" binding:"required"`
}

// ConfirmPayment — called by Flutter when the importer taps "Payment Done" after returning
// from their UPI app. Self-declared: no gateway signature to verify.
func (h *OrderHandler) ConfirmPayment(c *gin.Context) {
	importerID := c.GetString("user_id")

	var req confirmPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.orderService.ConfirmPaymentDone(c.Request.Context(), req.OrderID, importerID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	response.Success(c, http.StatusOK, gin.H{
		"message": "Payment recorded and held in escrow. Exporter has been notified to ship goods.",
	})
}

type confirmBankTransferRequest struct {
	OrderID   string `json:"order_id" binding:"required"`
	Reference string `json:"reference" binding:"required"`
}

// ConfirmBankTransfer — Journey 10 "bank transfer": importer self-declares having wired
// payment to the platform's bank account, with a reference/UTR for reconciliation.
func (h *OrderHandler) ConfirmBankTransfer(c *gin.Context) {
	importerID := c.GetString("user_id")

	var req confirmBankTransferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.orderService.ConfirmBankTransfer(c.Request.Context(), req.OrderID, importerID, req.Reference); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	response.Success(c, http.StatusOK, gin.H{
		"message": "Bank transfer recorded and held in escrow, pending verification. Exporter has been notified to ship goods.",
	})
}

// GetBankTransferDetails — the platform's bank account for the importer to wire payment to.
func (h *OrderHandler) GetBankTransferDetails(c *gin.Context) {
	response.Success(c, http.StatusOK, h.orderService.BankTransferDetails())
}

type createStripeIntentRequest struct {
	OrderID string `json:"order_id" binding:"required"`
}

// CreateStripePaymentIntent — Journey 10 "Stripe": international/card payment alternative.
func (h *OrderHandler) CreateStripePaymentIntent(c *gin.Context) {
	importerID := c.GetString("user_id")
	var req createStripeIntentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	intent, err := h.orderService.CreateStripePaymentIntent(c.Request.Context(), req.OrderID, importerID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, intent)
}

type confirmDeliveryRequest struct {
	OrderID string `json:"order_id" binding:"required"`
}

// ConfirmDelivery — importer confirms goods received -> releases escrow (payout is
// processed manually by the platform outside the app).
func (h *OrderHandler) ConfirmDelivery(c *gin.Context) {
	importerID := c.GetString("user_id")

	var req confirmDeliveryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.orderService.ConfirmDeliveryAndRelease(c.Request.Context(), req.OrderID, importerID, true); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	response.Success(c, http.StatusOK, gin.H{
		"message": "Delivery confirmed. Payment release approved for the exporter.",
	})
}

// GetEscrowStatus — the order's own importer/exporter can check escrow status + the
// auto-release due date (Order Details screen's "Awaiting Buyer Confirmation — Auto
// Release Due In X Days" banner), without needing the admin-only escrow endpoints.
func (h *OrderHandler) GetEscrowStatus(c *gin.Context) {
	userID := c.GetString("user_id")
	escrow, err := h.orderService.GetEscrowStatus(c.Request.Context(), c.Param("id"), userID)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, escrow)
}
