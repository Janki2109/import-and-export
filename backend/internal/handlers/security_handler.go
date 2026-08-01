package handlers

import (
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
)

type SecurityHandler struct {
	securityService *services.SecurityService
	docSecurity     *services.DocumentSecurityService
}

func NewSecurityHandler(securityService *services.SecurityService, docSecurity *services.DocumentSecurityService) *SecurityHandler {
	return &SecurityHandler{securityService: securityService, docSecurity: docSecurity}
}

// GetOverview — GET /security/overview. Backs the Security Dashboard screen (Part 12).
func (h *SecurityHandler) GetOverview(c *gin.Context) {
	userID := c.GetString("user_id")
	overview, err := h.securityService.GetOverview(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, overview)
}

func (h *SecurityHandler) ListDevices(c *gin.Context) {
	userID := c.GetString("user_id")
	devices, err := h.securityService.ListDevices(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, devices)
}

func (h *SecurityHandler) TrustDevice(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.securityService.TrustDevice(c.Request.Context(), userID, c.Param("id"), true); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "device marked as trusted"})
}

func (h *SecurityHandler) LogoutDevice(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.securityService.LogoutDevice(c.Request.Context(), userID, c.Param("id")); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "device logged out"})
}

type secureUrlRequest struct {
	Key string `json:"key" binding:"required"`
}

// GetSecureDownloadUrl — POST /documents/secure-url. Issues a short-lived, signed download
// link for a storage key (Part 3/10 — "no public URLs, signed URLs, expiry time"). Callers
// (Compliance Center, KYC, order documents, etc.) are responsible for verifying the
// requesting user is actually allowed to see that specific document *before* calling this —
// this layer only knows about storage keys, not RFQ/order/KYC ownership (Part 4's RBAC is
// enforced by the calling service, matching this backend's existing service-owns-its-domain
// architecture).
func (h *SecurityHandler) GetSecureDownloadUrl(c *gin.Context) {
	var req secureUrlRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	url := h.docSecurity.GenerateDownloadUrl(req.Key, scheme+"://"+c.Request.Host)
	response.Success(c, http.StatusOK, gin.H{"url": url})
}

// DownloadSecure — GET /documents/secure/*key?token=...&expires_in=... Deliberately outside
// the JWT-protected group (the signed token IS the authorization, exactly like the existing
// local-storage upload endpoint) — but every fetch is still logged with whatever identity
// info is available (Authorization header if the client happens to send one, else anonymous).
func (h *SecurityHandler) DownloadSecure(c *gin.Context) {
	key := c.Param("key")
	if len(key) > 0 && key[0] == '/' {
		key = key[1:]
	}
	token := c.Query("token")
	if key == "" || token == "" {
		response.Error(c, http.StatusBadRequest, "missing key or token")
		return
	}
	meta := security.ExtractRequestMeta(c)
	userID := c.GetString("user_id") // set only if AuthOrAPIKey-style middleware ran; fine if empty
	reader, err := h.docSecurity.Fetch(c.Request.Context(), key, token, "download", userID, meta.IP)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	defer reader.Close()
	c.Header("Content-Disposition", "attachment")
	c.Header("X-Content-Type-Options", "nosniff")
	if _, err := io.Copy(c.Writer, reader); err != nil {
		response.Error(c, http.StatusInternalServerError, "failed to stream document")
	}
}
