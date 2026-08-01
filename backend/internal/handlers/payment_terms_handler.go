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

type PaymentTermsHandler struct {
	svc *services.PaymentTermsService
}

func NewPaymentTermsHandler(svc *services.PaymentTermsService) *PaymentTermsHandler {
	return &PaymentTermsHandler{svc: svc}
}

type milestoneInputRequest struct {
	Title         string  `json:"title" binding:"required"`
	Percentage    float64 `json:"percentage" binding:"required"`
	TriggerEvent  string  `json:"trigger_event"`
	ProofRequired bool    `json:"proof_required"`
}

type setupPaymentTermsRequest struct {
	OrderID         string                  `json:"order_id" binding:"required"`
	PaymentModel    string                  `json:"payment_model" binding:"required"`
	Currency        string                  `json:"currency"`
	Milestones      []milestoneInputRequest `json:"milestones"`
	LCNumber        *string                 `json:"lc_number"`
	LCBankName      *string                 `json:"lc_bank_name"`
	LCExpiryDate    *string                 `json:"lc_expiry_date"`
	OpenAccountDays *int                    `json:"open_account_days"`
}

// Setup — POST /payment-terms/setup. Called once, right after order creation, by either
// party. Locks the negotiated payment model + milestone schedule for the order.
func (h *PaymentTermsHandler) Setup(c *gin.Context) {
	actorID := c.GetString("user_id")
	role := c.GetString("role")
	var req setupPaymentTermsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	var milestones []services.MilestoneInput
	for _, m := range req.Milestones {
		milestones = append(milestones, services.MilestoneInput{
			Title: m.Title, Percentage: m.Percentage, TriggerEvent: m.TriggerEvent, ProofRequired: m.ProofRequired,
		})
	}
	var expiry *time.Time
	if req.LCExpiryDate != nil && *req.LCExpiryDate != "" {
		if t, err := time.Parse("2006-01-02", *req.LCExpiryDate); err == nil {
			expiry = &t
		}
	}
	terms, ms, err := h.svc.Setup(c.Request.Context(), actorID, role, services.SetupInput{
		OrderID:         req.OrderID,
		PaymentModel:    models.PaymentModel(req.PaymentModel),
		Currency:        req.Currency,
		Milestones:      milestones,
		LCNumber:        req.LCNumber,
		LCBankName:      req.LCBankName,
		LCExpiryDate:    expiry,
		OpenAccountDays: req.OpenAccountDays,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, gin.H{"payment_terms": terms, "milestones": ms})
}

// GetByOrder — GET /payment-terms/by-order/:orderId.
func (h *PaymentTermsHandler) GetByOrder(c *gin.Context) {
	terms, ms, err := h.svc.GetByOrderID(c.Request.Context(), c.Param("orderId"))
	if err != nil {
		response.Error(c, http.StatusNotFound, "payment terms not set up for this order")
		return
	}
	response.Success(c, http.StatusOK, gin.H{"payment_terms": terms, "milestones": ms})
}

func (h *PaymentTermsHandler) Pay(c *gin.Context) {
	importerID := c.GetString("user_id")
	if err := h.svc.PayMilestone(c.Request.Context(), c.Param("id"), importerID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "milestone payment recorded"})
}

type uploadProofRequest struct {
	ProofURL string `json:"proof_url" binding:"required"`
}

func (h *PaymentTermsHandler) UploadProof(c *gin.Context) {
	exporterID := c.GetString("user_id")
	var req uploadProofRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.svc.UploadProof(c.Request.Context(), c.Param("id"), exporterID, req.ProofURL); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "proof uploaded"})
}

type remarksRequest struct {
	Remarks string `json:"remarks"`
}

func (h *PaymentTermsHandler) Approve(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req remarksRequest
	_ = c.ShouldBindJSON(&req)
	var remarks *string
	if req.Remarks != "" {
		remarks = &req.Remarks
	}
	if err := h.svc.Approve(c.Request.Context(), c.Param("id"), adminID, remarks); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "milestone approved"})
}

func (h *PaymentTermsHandler) Reject(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req remarksRequest
	_ = c.ShouldBindJSON(&req)
	var remarks *string
	if req.Remarks != "" {
		remarks = &req.Remarks
	}
	if err := h.svc.Reject(c.Request.Context(), c.Param("id"), adminID, remarks); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "milestone rejected"})
}

func (h *PaymentTermsHandler) Hold(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req remarksRequest
	_ = c.ShouldBindJSON(&req)
	var remarks *string
	if req.Remarks != "" {
		remarks = &req.Remarks
	}
	if err := h.svc.Hold(c.Request.Context(), c.Param("id"), adminID, remarks); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "milestone held"})
}

func (h *PaymentTermsHandler) Unhold(c *gin.Context) {
	if err := h.svc.Unhold(c.Request.Context(), c.Param("id")); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "milestone unheld"})
}

func (h *PaymentTermsHandler) Release(c *gin.Context) {
	adminID := c.GetString("user_id")
	m, err := h.svc.Release(c.Request.Context(), c.Param("id"), adminID)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"milestone": m})
}

type updateLCRequest struct {
	LCNumber   *string `json:"lc_number"`
	LCBankName *string `json:"lc_bank_name"`
	LCExpiry   *string `json:"lc_expiry_date"`
	LCStatus   *string `json:"lc_status"`
}

func (h *PaymentTermsHandler) UpdateLC(c *gin.Context) {
	actorID := c.GetString("user_id")
	role := c.GetString("role")
	var req updateLCRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	var status *models.LCStatus
	if req.LCStatus != nil {
		s := models.LCStatus(*req.LCStatus)
		status = &s
	}
	if err := h.svc.UpdateLC(c.Request.Context(), c.Param("id"), actorID, role, req.LCNumber, req.LCBankName, req.LCExpiry, status); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "LC details updated"})
}

// ---- Admin ----

func (h *PaymentTermsHandler) AdminList(c *gin.Context) {
	rows, err := h.svc.AdminList(c.Request.Context(), repository.AdminPaymentFilters{
		PaymentModel: c.Query("payment_model"),
		Search:       c.Query("search"),
	})
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rows)
}

func (h *PaymentTermsHandler) AdminSummary(c *gin.Context) {
	s, err := h.svc.AdminSummary(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, s)
}
