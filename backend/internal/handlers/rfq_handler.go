package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type RFQHandler struct {
	rfqService *services.RFQService
}

func NewRFQHandler(rfqService *services.RFQService) *RFQHandler {
	return &RFQHandler{rfqService: rfqService}
}

type createRFQRequest struct {
	ProductName        string   `json:"product_name" binding:"required"`
	HSNCode            *string  `json:"hsn_code"`
	Quantity           float64  `json:"quantity" binding:"required,gt=0"`
	Unit               string   `json:"unit" binding:"required"`
	TargetPrice        *float64 `json:"target_price"`
	DestinationCountry string   `json:"destination_country" binding:"required"`
	Description        *string  `json:"description"`
	ProductImageURL    *string  `json:"product_image_url"`
	// TargetExporterIDs — optional; when set, this RFQ is sent only to these exporters
	// (Journey 3: "request quotation" from a specific company profile) instead of the open
	// marketplace broadcast.
	TargetExporterIDs []string `json:"target_exporter_ids"`
}

// CreateRFQ — importer only.
func (h *RFQHandler) CreateRFQ(c *gin.Context) {
	importerID := c.GetString("user_id")

	var req createRFQRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	rfq, err := h.rfqService.CreateRFQ(c.Request.Context(), services.CreateRFQInput{
		ImporterID:         importerID,
		ProductName:        req.ProductName,
		HSNCode:            req.HSNCode,
		Quantity:           req.Quantity,
		Unit:               req.Unit,
		TargetPrice:        req.TargetPrice,
		DestinationCountry: req.DestinationCountry,
		Description:        req.Description,
		ProductImageURL:    req.ProductImageURL,
		TargetExporterIDs:  req.TargetExporterIDs,
	})
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, rfq)
}

// ListOpenRFQs — browsed by exporters looking for RFQs to quote against. Only RFQs that are
// either untargeted (open marketplace) or specifically targeted at this exporter are returned.
func (h *RFQHandler) ListOpenRFQs(c *gin.Context) {
	exporterID := c.GetString("user_id")
	rfqs, err := h.rfqService.ListOpen(c.Request.Context(), exporterID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rfqs)
}

// ListMyRFQs — importer's own RFQs.
func (h *RFQHandler) ListMyRFQs(c *gin.Context) {
	importerID := c.GetString("user_id")
	rfqs, err := h.rfqService.ListMine(c.Request.Context(), importerID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rfqs)
}

func (h *RFQHandler) GetRFQ(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	rfq, err := h.rfqService.GetByID(c.Request.Context(), c.Param("id"), userID, role)
	if err != nil {
		response.Error(c, http.StatusNotFound, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rfq)
}
