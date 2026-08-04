package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type ComplianceHandler struct {
	svc *services.ComplianceService
}

func NewComplianceHandler(svc *services.ComplianceService) *ComplianceHandler {
	return &ComplianceHandler{svc: svc}
}

// GetForOrder — GET /orders/:id/compliance. Also returns shipment-block status so the
// Order Details "Compliance" section can render the progress bar + blocked banner in one call.
func (h *ComplianceHandler) GetForOrder(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	orderID := c.Param("id")

	items, err := h.svc.GetForOrder(c.Request.Context(), orderID, userID, role, baseURL(c))
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	blocked, missing, err := h.svc.ShipmentBlockStatus(c.Request.Context(), orderID, userID, role)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}

	total := len(items)
	verified := 0
	for _, it := range items {
		if it.Status == models.ComplianceVerified {
			verified++
		}
	}
	progress := 0
	if total > 0 {
		progress = (verified * 100) / total
	}

	response.Success(c, http.StatusOK, gin.H{
		"items":             items,
		"progress_percent":  progress,
		"shipment_blocked":  blocked,
		"missing_mandatory": missing,
	})
}

type uploadComplianceRequest struct {
	FileURL string  `json:"file_url"`
	Remarks *string `json:"remarks"`
}

// UploadDocument — POST /compliance/upload/:id
func (h *ComplianceHandler) UploadDocument(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))

	var req uploadComplianceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if req.FileURL == "" {
		response.Error(c, http.StatusBadRequest, "file_url is required")
		return
	}
	if err := h.svc.UploadDocument(c.Request.Context(), c.Param("id"), userID, role, req.FileURL, req.Remarks); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "document uploaded"})
}

// GetHistory — GET /compliance/history/:id
func (h *ComplianceHandler) GetHistory(c *gin.Context) {
	userID := c.GetString("user_id")
	role := models.UserRole(c.GetString("role"))
	history, err := h.svc.ListHistory(c.Request.Context(), c.Param("id"), userID, role, baseURL(c))
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, history)
}

// ---------------- Admin ----------------

// VerifyDocument — POST /admin/compliance/verify/:id
func (h *ComplianceHandler) VerifyDocument(c *gin.Context) {
	adminID := c.GetString("user_id")
	if err := h.svc.VerifyDocument(c.Request.Context(), c.Param("id"), adminID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "document verified"})
}

type rejectComplianceRequest struct {
	Remarks string `json:"remarks"`
}

// RejectDocument — POST /admin/compliance/reject/:id
func (h *ComplianceHandler) RejectDocument(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req rejectComplianceRequest
	_ = c.ShouldBindJSON(&req)
	if req.Remarks == "" {
		req.Remarks = "Document rejected by admin"
	}
	if err := h.svc.RejectDocument(c.Request.Context(), c.Param("id"), adminID, req.Remarks); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "document rejected"})
}

// AdminList — GET /admin/compliance
func (h *ComplianceHandler) AdminList(c *gin.Context) {
	f := repository.AdminComplianceFilters{}
	if v := c.Query("status"); v != "" {
		f.Status = &v
	}
	if v := c.Query("order_id"); v != "" {
		f.OrderID = &v
	}
	if v := c.Query("country"); v != "" {
		f.Country = &v
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

// AdminSummary — GET /admin/compliance/summary
func (h *ComplianceHandler) AdminSummary(c *gin.Context) {
	summary, err := h.svc.Summary(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, summary)
}

// ---------------- Rule management (admin-only) ----------------

// ListRules — GET /admin/compliance-rules
func (h *ComplianceHandler) ListRules(c *gin.Context) {
	rules, err := h.svc.ListRules(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rules)
}

type createRuleRequest struct {
	OriginCountry      *string `json:"origin_country"`
	DestinationCountry *string `json:"destination_country"`
	HSCode             *string `json:"hs_code"`
	ShippingMode       *string `json:"shipping_mode"`
	DocumentName       string  `json:"document_name"`
	ResponsibleRole    string  `json:"responsible_role"`
	Mandatory          bool    `json:"mandatory"`
	DisplayOrder       int     `json:"display_order"`
	Description        *string `json:"description"`
}

// CreateRule — POST /admin/compliance-rules. This is how new trade lanes (e.g. Japan ->
// Brazil) are supported without any code change — only a new row here.
func (h *ComplianceHandler) CreateRule(c *gin.Context) {
	var req createRuleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if req.DocumentName == "" || req.ResponsibleRole == "" {
		response.Error(c, http.StatusBadRequest, "document_name and responsible_role are required")
		return
	}
	rule := &models.ComplianceRule{
		OriginCountry: req.OriginCountry, DestinationCountry: req.DestinationCountry,
		HSCode: req.HSCode, ShippingMode: req.ShippingMode,
		DocumentName: req.DocumentName, ResponsibleRole: models.UserRole(req.ResponsibleRole),
		Mandatory: req.Mandatory, DisplayOrder: req.DisplayOrder, Description: req.Description,
	}
	if err := h.svc.CreateRule(c.Request.Context(), rule); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, rule)
}

// DeleteRule — DELETE /admin/compliance-rules/:id
func (h *ComplianceHandler) DeleteRule(c *gin.Context) {
	if err := h.svc.DeleteRule(c.Request.Context(), c.Param("id")); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "rule deleted"})
}
