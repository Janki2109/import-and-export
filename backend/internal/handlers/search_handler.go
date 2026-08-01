package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type SearchHandler struct {
	searchService *services.SearchService
	aiService     *services.AISearchService
}

func NewSearchHandler(searchService *services.SearchService, aiService *services.AISearchService) *SearchHandler {
	return &SearchHandler{searchService: searchService, aiService: aiService}
}

func (h *SearchHandler) SearchHSCodes(c *gin.Context) {
	query := c.Query("q")
	results, err := h.searchService.SearchHSCodes(c.Request.Context(), query)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, results)
}

func (h *SearchHandler) ListGSTRates(c *gin.Context) {
	rates, err := h.searchService.ListGSTRates(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rates)
}

func (h *SearchHandler) SearchCountries(c *gin.Context) {
	query := c.Query("q")
	results, err := h.searchService.SearchCountries(c.Request.Context(), query)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, results)
}

func (h *SearchHandler) ListPolicies(c *gin.Context) {
	countryID := c.Query("country_id")
	hsChapter := c.Query("hs_chapter")
	policyType := c.Query("policy_type")

	policies, err := h.searchService.ListPolicies(c.Request.Context(), countryID, hsChapter, policyType)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, policies)
}

func (h *SearchHandler) CalculateDuty(c *gin.Context) {
	hsCode := c.Query("hs_code")
	value, err := strconv.ParseFloat(c.Query("assessable_value"), 64)
	if hsCode == "" || err != nil {
		response.Error(c, http.StatusBadRequest, "hs_code and numeric assessable_value are required")
		return
	}

	breakdown, err := h.searchService.CalculateDuty(c.Request.Context(), hsCode, value)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, breakdown)
}

func (h *SearchHandler) CalculateFreight(c *gin.Context) {
	mode := c.Query("mode")
	weight, err1 := strconv.ParseFloat(c.Query("weight_kg"), 64)
	length, err2 := strconv.ParseFloat(c.DefaultQuery("length_cm", "0"), 64)
	width, err3 := strconv.ParseFloat(c.DefaultQuery("width_cm", "0"), 64)
	height, err4 := strconv.ParseFloat(c.DefaultQuery("height_cm", "0"), 64)
	if err1 != nil || err2 != nil || err3 != nil || err4 != nil {
		response.Error(c, http.StatusBadRequest, "invalid numeric parameters")
		return
	}

	estimate, err := h.searchService.CalculateFreight(mode, weight, length, width, height)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, estimate)
}

type landedCostRequest struct {
	HSCode       string  `json:"hs_code" binding:"required"`
	FOBValue     float64 `json:"fob_value" binding:"required,gt=0"`
	Freight      float64 `json:"freight"`
	Insurance    float64 `json:"insurance"`
	OtherCharges float64 `json:"other_charges"`
}

func (h *SearchHandler) CalculateLandedCost(c *gin.Context) {
	var req landedCostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	breakdown, err := h.searchService.CalculateLandedCost(c.Request.Context(), req.HSCode, req.FOBValue, req.Freight, req.Insurance, req.OtherCharges)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, breakdown)
}

func (h *SearchHandler) AIProductSearch(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		response.Error(c, http.StatusBadRequest, "q (product description) is required")
		return
	}

	result, err := h.aiService.Search(c.Request.Context(), query)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, result)
}
