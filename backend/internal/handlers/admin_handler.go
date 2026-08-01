package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type AdminHandler struct {
	adminService *services.AdminService
	fraudService *services.FraudService
}

func NewAdminHandler(adminService *services.AdminService, fraudService *services.FraudService) *AdminHandler {
	return &AdminHandler{adminService: adminService, fraudService: fraudService}
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	var role *string
	if r := c.Query("role"); r != "" {
		role = &r
	}
	users, err := h.adminService.ListUsers(c.Request.Context(), role)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, users)
}

func (h *AdminHandler) ListUsersRich(c *gin.Context) {
	var role *string
	if r := c.Query("role"); r != "" {
		role = &r
	}
	users, err := h.adminService.ListUsersRich(c.Request.Context(), role)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, users)
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	if err := h.adminService.DeleteUser(c.Request.Context(), c.Param("id")); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "user deleted"})
}

type setUserActiveRequest struct {
	Active bool `json:"active"`
}

func (h *AdminHandler) SetUserActive(c *gin.Context) {
	userID := c.Param("id")
	var req setUserActiveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.adminService.SetUserActive(c.Request.Context(), userID, req.Active); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "user updated"})
}

func (h *AdminHandler) ListOrders(c *gin.Context) {
	var status *string
	if st := c.Query("status"); st != "" {
		status = &st
	}
	orders, err := h.adminService.ListOrders(c.Request.Context(), status)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, orders)
}

func (h *AdminHandler) ListOrdersRich(c *gin.Context) {
	var status *string
	if st := c.Query("status"); st != "" {
		status = &st
	}
	orders, err := h.adminService.ListOrdersRich(c.Request.Context(), status)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, orders)
}

func (h *AdminHandler) ListQuotations(c *gin.Context) {
	quotations, err := h.adminService.ListQuotations(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, quotations)
}

func (h *AdminHandler) ListWallets(c *gin.Context) {
	wallets, err := h.adminService.ListWallets(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, wallets)
}

func (h *AdminHandler) ListWithdrawals(c *gin.Context) {
	withdrawals, err := h.adminService.ListWithdrawals(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, withdrawals)
}

func (h *AdminHandler) ApproveWithdrawal(c *gin.Context) {
	adminID := c.GetString("user_id")
	if err := h.adminService.MarkWithdrawalPaid(c.Request.Context(), c.Param("id"), adminID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "withdrawal marked as paid"})
}

type rejectWithdrawalRequest struct {
	Reason string `json:"reason"`
}

func (h *AdminHandler) RejectWithdrawal(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req rejectWithdrawalRequest
	_ = c.ShouldBindJSON(&req)
	if req.Reason == "" {
		req.Reason = "Rejected by admin"
	}
	if err := h.adminService.RejectWithdrawal(c.Request.Context(), c.Param("id"), adminID, req.Reason); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "withdrawal rejected and refunded"})
}

func (h *AdminHandler) GetAnalytics(c *gin.Context) {
	analytics, err := h.adminService.GetAnalytics(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, analytics)
}

// GetChartAnalytics feeds the admin dashboard's chart section (monthly orders/revenue,
// country-wise RFQ trade, RFQ trend, top export categories, plus a few extra live counts).
func (h *AdminHandler) GetChartAnalytics(c *gin.Context) {
	charts, err := h.adminService.GetChartAnalytics(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, charts)
}

// ---------------- RFQ Management (admin-wide, read + delete) ----------------

func (h *AdminHandler) ListAllRFQs(c *gin.Context) {
	rfqs, err := h.adminService.ListRFQs(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rfqs)
}

func (h *AdminHandler) DeleteRFQ(c *gin.Context) {
	if err := h.adminService.DeleteRFQ(c.Request.Context(), c.Param("id")); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "rfq deleted"})
}

// ---------------- Shipment Management (admin-wide, read-only) ----------------

func (h *AdminHandler) ListAllShipments(c *gin.Context) {
	shipments, err := h.adminService.ListShipments(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, shipments)
}

// ---------------- Escrow (Admin Escrow Wallet) ----------------

func (h *AdminHandler) ListEscrowOrders(c *gin.Context) {
	var status *string
	if st := c.Query("status"); st != "" {
		status = &st
	}
	rows, err := h.adminService.ListEscrowOrders(c.Request.Context(), status)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rows)
}

func (h *AdminHandler) GetEscrowSummary(c *gin.Context) {
	summary, err := h.adminService.GetEscrowSummary(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, summary)
}

func (h *AdminHandler) ReleasePayment(c *gin.Context) {
	adminID := c.GetString("user_id")
	if err := h.adminService.ReleasePayment(c.Request.Context(), c.Param("id"), adminID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "payment released to exporter"})
}

func (h *AdminHandler) HoldPayment(c *gin.Context) {
	adminID := c.GetString("user_id")
	if err := h.adminService.HoldPayment(c.Request.Context(), c.Param("id"), adminID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "payment placed on hold"})
}

type refundPaymentRequest struct {
	Reason string `json:"reason" binding:"required"`
}

func (h *AdminHandler) RefundPayment(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req refundPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.adminService.RefundPayment(c.Request.Context(), c.Param("id"), adminID, req.Reason); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "payment refunded to importer"})
}

// GetEscrowHistory — audit trail for one order's escrow lifecycle.
func (h *AdminHandler) GetEscrowHistory(c *gin.Context) {
	logs, err := h.adminService.GetEscrowHistory(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, logs)
}

func (h *AdminHandler) GetFraudSignals(c *gin.Context) {
	signals, err := h.fraudService.GetSignals(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, signals)
}

type moderateProductRequest struct {
	Active bool `json:"active"`
}

func (h *AdminHandler) ModerateProduct(c *gin.Context) {
	productID := c.Param("id")
	var req moderateProductRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.adminService.ModerateProduct(c.Request.Context(), productID, req.Active); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "product updated"})
}

type createHSCodeRequest struct {
	Code                    string  `json:"code" binding:"required"`
	Description             string  `json:"description" binding:"required"`
	Chapter                 string  `json:"chapter" binding:"required"`
	BasicCustomsDutyPercent float64 `json:"basic_customs_duty_percent"`
	IGSTPercent             float64 `json:"igst_percent"`
}

func (h *AdminHandler) CreateHSCode(c *gin.Context) {
	var req createHSCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	hs, err := h.adminService.CreateHSCode(c.Request.Context(), req.Code, req.Description, req.Chapter, req.BasicCustomsDutyPercent, req.IGSTPercent)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, hs)
}

func (h *AdminHandler) DeleteHSCode(c *gin.Context) {
	if err := h.adminService.DeleteHSCode(c.Request.Context(), c.Param("id")); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "hs code removed"})
}

type createCountryRequest struct {
	Name         string  `json:"name" binding:"required"`
	ISO2         string  `json:"iso2" binding:"required"`
	ISO3         string  `json:"iso3" binding:"required"`
	Region       string  `json:"region" binding:"required"`
	IsRestricted bool    `json:"is_restricted"`
	Notes        *string `json:"notes"`
}

func (h *AdminHandler) CreateCountry(c *gin.Context) {
	var req createCountryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	country, err := h.adminService.CreateCountry(c.Request.Context(), req.Name, req.ISO2, req.ISO3, req.Region, req.IsRestricted, req.Notes)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, country)
}

type setCountryRestrictedRequest struct {
	Restricted bool `json:"restricted"`
}

func (h *AdminHandler) SetCountryRestricted(c *gin.Context) {
	var req setCountryRestrictedRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.adminService.SetCountryRestricted(c.Request.Context(), c.Param("id"), req.Restricted); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "country updated"})
}

func (h *AdminHandler) DeleteCountry(c *gin.Context) {
	if err := h.adminService.DeleteCountry(c.Request.Context(), c.Param("id")); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "country removed"})
}

// ---------------- Settings ----------------

func (h *AdminHandler) GetSettings(c *gin.Context) {
	settings, hasSMTPPassword, err := h.adminService.GetSettings(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{
		"app_name":          settings.AppName,
		"logo_url":          settings.LogoURL,
		"support_email":     settings.SupportEmail,
		"currency":          settings.Currency,
		"smtp_host":         settings.SMTPHost,
		"smtp_port":         settings.SMTPPort,
		"smtp_username":     settings.SMTPUsername,
		"smtp_from":         settings.SMTPFrom,
		"has_smtp_password": hasSMTPPassword,
		"updated_at":        settings.UpdatedAt,
	})
}

type updateSettingsRequest struct {
	AppName      string  `json:"app_name"`
	LogoURL      *string `json:"logo_url"`
	SupportEmail *string `json:"support_email"`
	Currency     string  `json:"currency"`
	SMTPHost     *string `json:"smtp_host"`
	SMTPPort     *int    `json:"smtp_port"`
	SMTPUsername *string `json:"smtp_username"`
	SMTPPassword *string `json:"smtp_password"` // omitted/empty = keep existing
	SMTPFrom     *string `json:"smtp_from"`
}

func (h *AdminHandler) UpdateSettings(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req updateSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	settings := &models.PlatformSettings{
		AppName: req.AppName, LogoURL: req.LogoURL, SupportEmail: req.SupportEmail, Currency: req.Currency,
		SMTPHost: req.SMTPHost, SMTPPort: req.SMTPPort, SMTPUsername: req.SMTPUsername, SMTPFrom: req.SMTPFrom,
	}
	var newPassword *string
	if req.SMTPPassword != nil && *req.SMTPPassword != "" {
		newPassword = req.SMTPPassword
	}
	if err := h.adminService.UpdateSettings(c.Request.Context(), settings, adminID, newPassword); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "settings updated"})
}

// ---------------- Notification broadcast ----------------

type broadcastNotificationRequest struct {
	TargetRole *string `json:"target_role"` // null = all users
	Title      string  `json:"title"`
	Body       string  `json:"body"`
	InApp      bool    `json:"in_app"`
	Email      bool    `json:"email"`
}

func (h *AdminHandler) BroadcastNotification(c *gin.Context) {
	var req broadcastNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if req.Title == "" || req.Body == "" {
		response.Error(c, http.StatusBadRequest, "title and body are required")
		return
	}
	if !req.InApp && !req.Email {
		response.Error(c, http.StatusBadRequest, "select at least one channel")
		return
	}
	inAppCount, emailCount, err := h.adminService.BroadcastNotification(c.Request.Context(), req.TargetRole, req.Title, req.Body, req.InApp, req.Email)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"in_app_sent": inAppCount, "email_sent": emailCount})
}

// ---------------- Logistics Management ----------------

func (h *AdminHandler) ListLogistics(c *gin.Context) {
	rows, err := h.adminService.ListLogistics(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rows)
}

// ---------------- Chat Management ----------------

func (h *AdminHandler) ListConversations(c *gin.Context) {
	rows, err := h.adminService.ListConversations(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, rows)
}

func (h *AdminHandler) GetConversationMessages(c *gin.Context) {
	messages, err := h.adminService.GetConversationMessages(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, messages)
}

type archiveConversationRequest struct {
	Archived bool `json:"archived"`
}

func (h *AdminHandler) ArchiveConversation(c *gin.Context) {
	var req archiveConversationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.adminService.SetConversationArchived(c.Request.Context(), c.Param("id"), req.Archived); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "conversation updated"})
}

func (h *AdminHandler) BlockUser(c *gin.Context) {
	if err := h.adminService.BlockUser(c.Request.Context(), c.Param("id")); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "user blocked"})
}

// ---------------- Global Search ----------------

func (h *AdminHandler) GlobalSearch(c *gin.Context) {
	q := c.Query("q")
	if len(q) < 2 {
		response.Success(c, http.StatusOK, []any{})
		return
	}
	results, err := h.adminService.GlobalSearch(c.Request.Context(), q)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, results)
}
