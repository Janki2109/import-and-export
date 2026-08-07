package handlers

import (
	"io"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
	"github.com/jayashri-infotech/onebharat-backend/pkg/utils"
)

type SecurityHandler struct {
	securityService *services.SecurityService
	docSecurity     *services.DocumentSecurityService
	jwtSecret       string
}

func NewSecurityHandler(securityService *services.SecurityService, docSecurity *services.DocumentSecurityService, jwtSecret string) *SecurityHandler {
	return &SecurityHandler{securityService: securityService, docSecurity: docSecurity, jwtSecret: jwtSecret}
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
// SECURITY FIX (H-02, IDOR): previously signed ANY storage key from the request body with no
// ownership check at all — any logged-in user could post e.g. {"key":"kyc/<userB-id>/pan.pdf"}
// (key formats are predictable — see UploadService.storageBucketFor) and receive a valid
// 15-minute signed URL for another user's document. This generic low-level endpoint has no
// caller left in the app (every document category now gets its signed URL from its own
// domain service — KYC/Compliance/Chat/PaymentTerms — which already enforces real
// order/KYC/conversation ownership before calling GenerateDownloadUrl internally), but rather
// than remove it outright, it's now restricted to keys already scoped under the requester's own
// user-id path segment (the common "<bucket>/<userID>/<file>" shape every upload category
// uses), with an admin bypass — closing the arbitrary-key IDOR without breaking the contract.
func (h *SecurityHandler) GetSecureDownloadUrl(c *gin.Context) {
	var req secureUrlRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	userID := c.GetString("user_id")
	role := c.GetString("role")
	if role != "admin" && !strings.Contains(req.Key, "/"+userID+"/") {
		response.Error(c, http.StatusForbidden, "not authorized to sign a download link for this key")
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
	// BUG FIX (L-01): this route deliberately runs with no auth middleware (the signed token IS
	// the authorization — see the route comment), so c.GetString("user_id") was ALWAYS empty
	// and the Security Dashboard's "recent document access" (filtered by user_id) could never
	// show a single download. Best-effort: if the client happens to send a still-valid Bearer
	// token anyway (the Flutter app usually does), decode it to attribute the log entry —
	// never required, never rejects the download if absent/invalid.
	userID := ""
	if auth := c.GetHeader("Authorization"); strings.HasPrefix(auth, "Bearer ") {
		if claims, err := utils.ParseToken(strings.TrimPrefix(auth, "Bearer "), h.jwtSecret); err == nil {
			userID = claims.UserID
		}
	}
	reader, err := h.docSecurity.Fetch(c.Request.Context(), key, token, "download", userID, meta.IP)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	defer reader.Close()
	c.Header("Content-Disposition", "attachment")
	c.Header("X-Content-Type-Options", "nosniff")
	// BUG FIX (L-02): previously called response.Error() (which writes a JSON body + tries to
	// set the status code) AFTER io.Copy had already started streaming bytes to the client —
	// the status/headers were already committed, so the client just received a truncated binary
	// with a JSON blob appended, and had no reliable way to detect the download had failed
	// mid-stream. Nothing can be done to un-send already-flushed bytes at this point; just log
	// server-side and stop writing.
	if _, err := io.Copy(c.Writer, reader); err != nil {
		log.Printf("secure document download: stream error for key %s: %v", key, err)
	}
}
