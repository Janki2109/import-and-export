package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type QuotationHandler struct {
	quotationService *services.QuotationService
}

func NewQuotationHandler(quotationService *services.QuotationService) *QuotationHandler {
	return &QuotationHandler{quotationService: quotationService}
}

type submitQuotationRequest struct {
	RFQID        string  `json:"rfq_id" binding:"required"`
	UnitPrice    float64 `json:"unit_price" binding:"required,gt=0"`
	Quantity     float64 `json:"quantity" binding:"required,gt=0"`
	ValidityDate string  `json:"validity_date" binding:"required"` // YYYY-MM-DD
	Terms        *string `json:"terms"`
}

// Submit — exporter quotes against an open RFQ.
func (h *QuotationHandler) Submit(c *gin.Context) {
	exporterID := c.GetString("user_id")

	var req submitQuotationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	validity, err := time.Parse("2006-01-02", req.ValidityDate)
	if err != nil {
		response.Error(c, http.StatusBadRequest, "validity_date must be in YYYY-MM-DD format")
		return
	}

	q, err := h.quotationService.Submit(c.Request.Context(), services.SubmitQuotationInput{
		RFQID:        req.RFQID,
		ExporterID:   exporterID,
		UnitPrice:    req.UnitPrice,
		Quantity:     req.Quantity,
		ValidityDate: validity,
		Terms:        req.Terms,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, q)
}

// ListForRFQ — importer views all quotations received for one of their RFQs.
func (h *QuotationHandler) ListForRFQ(c *gin.Context) {
	importerID := c.GetString("user_id")
	rfqID := c.Param("id")

	quotations, err := h.quotationService.ListForRFQ(c.Request.Context(), rfqID, importerID)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, quotations)
}

// ListMine — exporter views their own submitted quotations.
func (h *QuotationHandler) ListMine(c *gin.Context) {
	exporterID := c.GetString("user_id")
	quotations, err := h.quotationService.ListMine(c.Request.Context(), exporterID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, quotations)
}

type acceptQuotationRequest struct {
	DeliveryAddress *string `json:"delivery_address"`
	Notes           *string `json:"notes"`
}

// Accept — importer accepts a quotation, which creates the order + escrow row.
func (h *QuotationHandler) Accept(c *gin.Context) {
	importerID := c.GetString("user_id")
	quotationID := c.Param("id")

	var req acceptQuotationRequest
	_ = c.ShouldBindJSON(&req)

	order, err := h.quotationService.Accept(c.Request.Context(), quotationID, importerID, req.DeliveryAddress, req.Notes)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{
		"message": "Quotation accepted. Order created — proceed to escrow payment.",
		"order":   order,
	})
}
