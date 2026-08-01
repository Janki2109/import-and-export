package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type DocumentHandler struct {
	documentService *services.DocumentService
}

func NewDocumentHandler(documentService *services.DocumentService) *DocumentHandler {
	return &DocumentHandler{documentService: documentService}
}

type generateDocumentRequest struct {
	OrderID string `json:"order_id" binding:"required"`
	Type    string `json:"type" binding:"required,oneof=commercial_invoice packing_list certificate_of_origin bill_of_lading air_waybill shipping_invoice"`
}

// Generate — importer or exporter on the order generates a trade document PDF.
func (h *DocumentHandler) Generate(c *gin.Context) {
	userID := c.GetString("user_id")

	var req generateDocumentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	doc, err := h.documentService.Generate(c.Request.Context(), req.OrderID, models.DocumentType(req.Type), userID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, doc)
}

// ListForOrder — all generated documents for an order.
func (h *DocumentHandler) ListForOrder(c *gin.Context) {
	docs, err := h.documentService.ListForOrder(c.Request.Context(), c.Param("order_id"))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, docs)
}
