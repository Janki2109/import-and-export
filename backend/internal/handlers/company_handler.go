package handlers

import (
	"net/http"
	"strconv"

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
	CompanyName           string   `json:"company_name" binding:"required"`
	BusinessType          *string  `json:"business_type"`
	RegistrationNumber    *string  `json:"registration_number"`
	Address               *string  `json:"address"`
	City                  *string  `json:"city"`
	Country               *string  `json:"country"`
	Website               *string  `json:"website"`
	ProductsImported      *string  `json:"products_imported"`
	PreferredShippingMode *string  `json:"preferred_shipping_mode"`
	Certifications        []string `json:"certifications"`
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
		Certifications: req.Certifications,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, company)
}

// ListDirectory — GET /companies?search=... — Journey 3's importer-facing supplier directory.
func (h *CompanyHandler) ListDirectory(c *gin.Context) {
	search := c.Query("search")
	limit, offset := 50, 0
	if l, err := strconv.Atoi(c.Query("limit")); err == nil && l > 0 && l <= 100 {
		limit = l
	}
	if o, err := strconv.Atoi(c.Query("offset")); err == nil && o >= 0 {
		offset = o
	}
	list, err := h.companyService.ListDirectory(c.Request.Context(), search, limit, offset)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, list)
}

// GetProfile — GET /companies/:id — Journey 3's "open company profile": details, certifications,
// products, ratings, average response time, aggregated in one call.
func (h *CompanyHandler) GetProfile(c *gin.Context) {
	profile, err := h.companyService.GetProfile(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusNotFound, err.Error())
		return
	}
	response.Success(c, http.StatusOK, profile)
}

type rateCompanyRequest struct {
	OrderID string  `json:"order_id" binding:"required"`
	Score   int     `json:"score" binding:"required,min=1,max=5"`
	Comment *string `json:"comment"`
}

// RateCompany — POST /companies/:id/ratings — importer rates the exporter after order completion.
func (h *CompanyHandler) RateCompany(c *gin.Context) {
	userID := c.GetString("user_id")
	var req rateCompanyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	rating, err := h.companyService.RateCompany(c.Request.Context(), c.Param("id"), req.OrderID, userID, req.Score, req.Comment)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, rating)
}

// ListRatings — GET /companies/:id/ratings.
func (h *CompanyHandler) ListRatings(c *gin.Context) {
	ratings, err := h.companyService.ListRatings(c.Request.Context(), c.Param("id"), 50, 0)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, ratings)
}
