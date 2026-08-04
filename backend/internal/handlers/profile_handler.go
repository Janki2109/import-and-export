package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type ProfileHandler struct {
	profileService *services.ProfileService
}

func NewProfileHandler(profileService *services.ProfileService) *ProfileHandler {
	return &ProfileHandler{profileService: profileService}
}

// GetProfile — GET /users/me
func (h *ProfileHandler) GetProfile(c *gin.Context) {
	userID := c.GetString("user_id")
	user, err := h.profileService.GetProfile(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, user)
}

type updateProfileRequest struct {
	FullName  string  `json:"full_name" binding:"required"`
	Email     string  `json:"email" binding:"required,email"`
	Phone     string  `json:"phone" binding:"required"`
	AvatarURL *string `json:"avatar_url"`
}

// UpdateProfile — PUT /users/me
func (h *ProfileHandler) UpdateProfile(c *gin.Context) {
	userID := c.GetString("user_id")
	var req updateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	user, err := h.profileService.UpdateProfile(c.Request.Context(), services.UpdateProfileInput{
		UserID: userID, FullName: req.FullName, Email: req.Email, Phone: req.Phone, AvatarURL: req.AvatarURL,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, user)
}

type publicUser struct {
	ID          string  `json:"id"`
	FullName    string  `json:"full_name"`
	CompanyName *string `json:"company_name,omitempty"`
	Role        string  `json:"role"`
	AvatarURL   *string `json:"avatar_url,omitempty"`
	// ChatPublicKey — Journey 11 "end-to-end encrypted chat": this user's X25519 public key, so
	// any other user can derive a shared ECDH secret with them client-side. Safe to expose
	// publicly — it's a public key by definition, not sensitive.
	ChatPublicKey *string `json:"chat_public_key,omitempty"`
}

// GetPublicProfile — GET /users/public/:id. Trimmed, non-sensitive fields only (no email/
// phone) — used to show "Importer: <name>" / "Exporter: <name>" on shared screens like
// Order Details, where the viewer isn't necessarily that user.
func (h *ProfileHandler) GetPublicProfile(c *gin.Context) {
	user, err := h.profileService.GetProfile(c.Request.Context(), c.Param("id"))
	if err != nil {
		response.Error(c, http.StatusNotFound, "user not found")
		return
	}
	response.Success(c, http.StatusOK, publicUser{
		ID: user.ID, FullName: user.FullName, CompanyName: user.CompanyName,
		Role: string(user.Role), AvatarURL: user.AvatarURL, ChatPublicKey: user.ChatPublicKey,
	})
}

type setChatPublicKeyRequest struct {
	PublicKey string `json:"public_key" binding:"required"`
}

// SetChatPublicKey — POST /users/me/chat-public-key. Journey 11 "end-to-end encrypted chat":
// the client generates an X25519 keypair locally (private key never leaves the device) and
// publishes only the public key here.
func (h *ProfileHandler) SetChatPublicKey(c *gin.Context) {
	userID := c.GetString("user_id")
	var req setChatPublicKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.profileService.SetChatPublicKey(c.Request.Context(), userID, req.PublicKey); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "chat public key updated"})
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password" binding:"required,min=8"`
}

// ChangePassword — POST /users/me/change-password
func (h *ProfileHandler) ChangePassword(c *gin.Context) {
	userID := c.GetString("user_id")
	var req changePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.profileService.ChangePassword(c.Request.Context(), userID, req.CurrentPassword, req.NewPassword); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "Password changed successfully"})
}
