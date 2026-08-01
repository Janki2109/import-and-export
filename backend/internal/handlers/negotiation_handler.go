package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type NegotiationHandler struct {
	svc *services.NegotiationService
}

func NewNegotiationHandler(svc *services.NegotiationService) *NegotiationHandler {
	return &NegotiationHandler{svc: svc}
}

type rejectQuotationRequest struct {
	QuotationID string `json:"quotation_id" binding:"required"`
}

// RejectQuotation — POST /negotiations/reject-quotation. The importer's "Reject Quote"
// choice on the very first quotation, before negotiation starts.
func (h *NegotiationHandler) RejectQuotation(c *gin.Context) {
	importerID := c.GetString("user_id")
	var req rejectQuotationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.svc.RejectQuotation(c.Request.Context(), req.QuotationID, importerID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "quotation rejected"})
}

type startNegotiationRequest struct {
	QuotationID string `json:"quotation_id" binding:"required"`
}

// Start — POST /negotiations/start
func (h *NegotiationHandler) Start(c *gin.Context) {
	importerID := c.GetString("user_id")
	var req startNegotiationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	negotiation, err := h.svc.StartNegotiation(c.Request.Context(), req.QuotationID, importerID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, negotiation)
}

// GetByID — GET /negotiations/:id
func (h *NegotiationHandler) GetByID(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	negotiation, err := h.svc.GetByID(c.Request.Context(), c.Param("id"), userID, role)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, negotiation)
}

// GetHistory — GET /negotiations/history/:id — the structured timeline.
func (h *NegotiationHandler) GetHistory(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	offers, err := h.svc.GetTimeline(c.Request.Context(), c.Param("id"), userID, role)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, offers)
}

// ListMine — GET /negotiations/mine
func (h *NegotiationHandler) ListMine(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	negotiations, err := h.svc.ListMine(c.Request.Context(), userID, role)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, negotiations)
}

// GetByQuotation — GET /negotiations/by-quotation/:quotationId — lets the UI check whether
// a negotiation already exists for a quotation (to route "Negotiate" vs re-opening it).
func (h *NegotiationHandler) GetByQuotation(c *gin.Context) {
	negotiation, err := h.svc.GetByQuotationID(c.Request.Context(), c.Param("quotationId"))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, negotiation)
}

type counterOfferRequest struct {
	UnitPrice         float64    `json:"unit_price" binding:"required"`
	Currency          string     `json:"currency"`
	Quantity          float64    `json:"quantity" binding:"required"`
	MOQ               *float64   `json:"moq"`
	DeliveryDays      *int       `json:"delivery_days"`
	DispatchDays      *int       `json:"dispatch_days"`
	ShippingMode      *string    `json:"shipping_mode"`
	Incoterm          *string    `json:"incoterm"`
	PaymentTerms      *string    `json:"payment_terms"`
	Packaging         *string    `json:"packaging"`
	ValidityDate      *time.Time `json:"validity_date"`
	SpecialConditions *string    `json:"special_conditions"`
	Remarks           *string    `json:"remarks"`
}

// CounterOffer — POST /negotiations/counter/:id
func (h *NegotiationHandler) CounterOffer(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	var req counterOfferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	offer, err := h.svc.CounterOffer(c.Request.Context(), c.Param("id"), userID, role, services.OfferInput{
		UnitPrice: req.UnitPrice, Currency: req.Currency, Quantity: req.Quantity, MOQ: req.MOQ,
		DeliveryDays: req.DeliveryDays, DispatchDays: req.DispatchDays, ShippingMode: req.ShippingMode,
		Incoterm: req.Incoterm, PaymentTerms: req.PaymentTerms, Packaging: req.Packaging,
		ValidityDate: req.ValidityDate, SpecialConditions: req.SpecialConditions, Remarks: req.Remarks,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, offer)
}

// Accept — POST /negotiations/accept/:id
func (h *NegotiationHandler) Accept(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	if err := h.svc.AcceptOffer(c.Request.Context(), c.Param("id"), userID, role); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "offer accepted — final quotation locked"})
}

// Reject — POST /negotiations/reject/:id
func (h *NegotiationHandler) Reject(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	if err := h.svc.RejectOffer(c.Request.Context(), c.Param("id"), userID, role); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "offer rejected — negotiation closed"})
}

// Close — POST /negotiations/close/:id
func (h *NegotiationHandler) Close(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	if err := h.svc.CloseNegotiation(c.Request.Context(), c.Param("id"), userID, role); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "negotiation closed"})
}

// ---------------- Admin ----------------

// AdminForceClose — POST /admin/negotiations/force-close/:id
func (h *NegotiationHandler) AdminForceClose(c *gin.Context) {
	adminID := c.GetString("user_id")
	if err := h.svc.ForceClose(c.Request.Context(), c.Param("id"), adminID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "negotiation force-closed"})
}

// AdminList — GET /admin/negotiations
func (h *NegotiationHandler) AdminList(c *gin.Context) {
	f := repository.AdminNegotiationFilters{}
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	if v := c.Query("search"); v != "" {
		f.Search = &v
	}
	rows, err := h.svc.AdminList(c.Request.Context(), f)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rows)
}
