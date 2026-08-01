package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type MembershipHandler struct {
	membershipService *services.MembershipService
}

func NewMembershipHandler(membershipService *services.MembershipService) *MembershipHandler {
	return &MembershipHandler{membershipService: membershipService}
}

func (h *MembershipHandler) GetMine(c *gin.Context) {
	userID := c.GetString("user_id")
	m, err := h.membershipService.GetMine(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, m)
}

func (h *MembershipHandler) CreatePremiumOrder(c *gin.Context) {
	userID := c.GetString("user_id")
	order, err := h.membershipService.CreatePremiumOrder(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, order)
}

func (h *MembershipHandler) CreateFeaturedOrder(c *gin.Context) {
	userID := c.GetString("user_id")
	order, err := h.membershipService.CreateFeaturedOrder(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, order)
}

// VerifyPremiumPayment — the client calls this after returning from their UPI app and
// tapping "Payment Done". Self-declared, no gateway signature involved.
func (h *MembershipHandler) VerifyPremiumPayment(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.membershipService.VerifyPremiumPayment(c.Request.Context(), services.VerifyPurchaseInput{UserID: userID}); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "premium membership activated for 30 days"})
}

func (h *MembershipHandler) VerifyFeaturedPayment(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.membershipService.VerifyFeaturedPayment(c.Request.Context(), services.VerifyPurchaseInput{UserID: userID}); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "featured placement activated for 30 days"})
}

type createTierOrderRequest struct {
	Tier string `json:"tier" binding:"required,oneof=silver gold enterprise"`
}

func (h *MembershipHandler) CreateTierOrder(c *gin.Context) {
	userID := c.GetString("user_id")
	var req createTierOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	order, err := h.membershipService.CreateTierOrder(c.Request.Context(), userID, models.MembershipTier(req.Tier))
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, order)
}

type verifyTierPaymentRequest struct {
	Tier string `json:"tier" binding:"required,oneof=silver gold enterprise"`
}

func (h *MembershipHandler) VerifyTierPayment(c *gin.Context) {
	userID := c.GetString("user_id")
	var req verifyTierPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.membershipService.VerifyTierPayment(c.Request.Context(), services.VerifyPurchaseInput{UserID: userID}, models.MembershipTier(req.Tier)); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": req.Tier + " subscription activated for 30 days"})
}

// ListFeatured — public: ?role=exporter or ?role=logistics.
func (h *MembershipHandler) ListFeatured(c *gin.Context) {
	role := c.Query("role")
	if role == "" {
		response.Error(c, http.StatusBadRequest, "role query param is required")
		return
	}
	users, err := h.membershipService.ListFeatured(c.Request.Context(), role)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, users)
}

// ---------------- Advertisements ----------------

type AdvertisementHandler struct {
	adService *services.AdvertisementService
}

func NewAdvertisementHandler(adService *services.AdvertisementService) *AdvertisementHandler {
	return &AdvertisementHandler{adService: adService}
}

type createAdRequest struct {
	Title     string  `json:"title" binding:"required"`
	ImageURL  string  `json:"image_url" binding:"required"`
	TargetURL *string `json:"target_url"`
	EndsAt    *string `json:"ends_at"` // YYYY-MM-DD, optional
}

func (h *AdvertisementHandler) Create(c *gin.Context) {
	advertiserID := c.GetString("user_id")
	var req createAdRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	var endsAt *time.Time
	if req.EndsAt != nil && *req.EndsAt != "" {
		parsed, err := time.Parse("2006-01-02", *req.EndsAt)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "ends_at must be in YYYY-MM-DD format")
			return
		}
		endsAt = &parsed
	}

	ad, err := h.adService.Create(c.Request.Context(), services.CreateAdInput{
		AdvertiserID: advertiserID, Title: req.Title, ImageURL: req.ImageURL, TargetURL: req.TargetURL, EndsAt: endsAt,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, ad)
}

func (h *AdvertisementHandler) ListActive(c *gin.Context) {
	ads, err := h.adService.ListActive(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, ads)
}

func (h *AdvertisementHandler) ListMine(c *gin.Context) {
	advertiserID := c.GetString("user_id")
	ads, err := h.adService.ListMine(c.Request.Context(), advertiserID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, ads)
}

// ---------------- Audit Log ----------------

type AuditHandler struct {
	auditService *services.AuditService
}

func NewAuditHandler(auditService *services.AuditService) *AuditHandler {
	return &AuditHandler{auditService: auditService}
}

func (h *AuditHandler) List(c *gin.Context) {
	logs, err := h.auditService.List(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, logs)
}
