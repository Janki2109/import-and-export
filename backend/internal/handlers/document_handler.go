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
	Type    string `json:"type" binding:"required,oneof=commercial_invoice packing_list certificate_of_origin bill_of_lading air_waybill shipping_invoice export_declaration import_declaration inspection_certificate insurance_certificate"`
}

func baseURL(c *gin.Context) string {
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	return scheme + "://" + c.Request.Host
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

// ListForOrder — all generated documents for an order, each with a fresh signed download URL.
func (h *DocumentHandler) ListForOrder(c *gin.Context) {
	userID := c.GetString("user_id")
	docs, err := h.documentService.ListForOrder(c.Request.Context(), c.Param("order_id"), userID, baseURL(c))
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, docs)
}

// ListVersions — version history for one document.
func (h *DocumentHandler) ListVersions(c *gin.Context) {
	userID := c.GetString("user_id")
	versions, err := h.documentService.ListVersions(c.Request.Context(), c.Param("id"), userID, baseURL(c))
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, versions)
}

// Delete — removes a document and every stored version of it ("no orphan files").
func (h *DocumentHandler) Delete(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.documentService.Delete(c.Request.Context(), c.Param("id"), userID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "document deleted"})
}
