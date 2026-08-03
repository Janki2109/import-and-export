package handlers

import (
	"net/http"

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

type createOrderRequest struct {
	ExporterID      string  `json:"exporter_id" binding:"required"`
	ProductName     string  `json:"product_name" binding:"required"`
	HSNCode         *string `json:"hsn_code"`
	Quantity        float64 `json:"quantity" binding:"required,gt=0"`
	Unit            string  `json:"unit" binding:"required"`
	UnitPrice       float64 `json:"unit_price" binding:"required,gt=0"`
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

	order, escrow, upiLink, err := h.orderService.CreateOrder(c.Request.Context(), services.CreateOrderInput{
		ImporterID:      importerID,
		ExporterID:      req.ExporterID,
		ProductName:     req.ProductName,
		HSNCode:         req.HSNCode,
		Quantity:        req.Quantity,
		Unit:            req.Unit,
		UnitPrice:       req.UnitPrice,
		DeliveryAddress: req.DeliveryAddress,
		Notes:           req.Notes,
	})
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
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

	orders, err := h.orderService.ListMyOrders(c.Request.Context(), userID, role, statusPtr)
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
