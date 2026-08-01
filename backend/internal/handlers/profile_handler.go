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
		Role: string(user.Role), AvatarURL: user.AvatarURL,
	})
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
