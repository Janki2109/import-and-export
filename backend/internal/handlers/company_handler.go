package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type CompanyHandler struct {
	companyService *services.CompanyService
}

func NewCompanyHandler(companyService *services.CompanyService) *CompanyHandler {
	return &CompanyHandler{companyService: companyService}
}

// GetMine — returns null data if the onboarding "Create Company" step hasn't been done yet
// (the Flutter router uses this to decide whether to send the user there).
func (h *CompanyHandler) GetMine(c *gin.Context) {
	userID := c.GetString("user_id")
	company, err := h.companyService.GetMine(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, company)
}

type upsertCompanyRequest struct {
	CompanyName           string  `json:"company_name" binding:"required"`
	BusinessType          *string `json:"business_type"`
	RegistrationNumber    *string `json:"registration_number"`
	Address               *string `json:"address"`
	City                  *string `json:"city"`
	Country               *string `json:"country"`
	Website               *string `json:"website"`
	ProductsImported      *string `json:"products_imported"`
	PreferredShippingMode *string `json:"preferred_shipping_mode"`
}

func (h *CompanyHandler) Upsert(c *gin.Context) {
	userID := c.GetString("user_id")
	var req upsertCompanyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	company, err := h.companyService.Upsert(c.Request.Context(), services.UpsertCompanyInput{
		UserID: userID, CompanyName: req.CompanyName, BusinessType: req.BusinessType,
		RegistrationNumber: req.RegistrationNumber, Address: req.Address, City: req.City,
		Country: req.Country, Website: req.Website,
		ProductsImported: req.ProductsImported, PreferredShippingMode: req.PreferredShippingMode,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, company)
}
