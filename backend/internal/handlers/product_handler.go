package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type ProductHandler struct {
	productService *services.ProductService
}

func NewProductHandler(productService *services.ProductService) *ProductHandler {
	return &ProductHandler{productService: productService}
}

type upsertProductRequest struct {
	Name        string   `json:"name" binding:"required"`
	HSNCode     *string  `json:"hsn_code"`
	Description *string  `json:"description"`
	Unit        string   `json:"unit" binding:"required"`
	UnitPrice   float64  `json:"unit_price" binding:"required,gt=0"`
	MinOrderQty float64  `json:"min_order_qty"`
	ImageURL    *string  `json:"image_url"`
	IsActive    *bool    `json:"is_active"`
}

// Create — exporter adds a product to their catalog.
func (h *ProductHandler) Create(c *gin.Context) {
	exporterID := c.GetString("user_id")
	var req upsertProductRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	product, err := h.productService.Create(c.Request.Context(), services.UpsertProductInput{
		ExporterID: exporterID, Name: req.Name, HSNCode: req.HSNCode, Description: req.Description,
		Unit: req.Unit, UnitPrice: req.UnitPrice, MinOrderQty: req.MinOrderQty, ImageURL: req.ImageURL,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, product)
}

func (h *ProductHandler) ListMine(c *gin.Context) {
	exporterID := c.GetString("user_id")
	products, err := h.productService.ListMine(c.Request.Context(), exporterID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, products)
}

// Search — public catalog browse (importers), keyword search over active products.
func (h *ProductHandler) Search(c *gin.Context) {
	query := c.Query("q")
	products, err := h.productService.Search(c.Request.Context(), query)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, products)
}

func (h *ProductHandler) Update(c *gin.Context) {
	exporterID := c.GetString("user_id")
	id := c.Param("id")
	var req upsertProductRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.productService.Update(c.Request.Context(), id, services.UpsertProductInput{
		ExporterID: exporterID, Name: req.Name, HSNCode: req.HSNCode, Description: req.Description,
		Unit: req.Unit, UnitPrice: req.UnitPrice, MinOrderQty: req.MinOrderQty, ImageURL: req.ImageURL,
		IsActive: req.IsActive,
	}); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "product updated"})
}

func (h *ProductHandler) Delete(c *gin.Context) {
	exporterID := c.GetString("user_id")
	id := c.Param("id")
	if err := h.productService.Delete(c.Request.Context(), id, exporterID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "product removed"})
}
