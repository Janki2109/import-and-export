package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
	"github.com/jayashri-infotech/onebharat-backend/pkg/security"
)

type AuthHandler struct {
	authService *services.AuthService
}

func NewAuthHandler(authService *services.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

type registerRequest struct {
	Role        string  `json:"role" binding:"required,oneof=importer exporter logistics"`
	FullName    string  `json:"full_name" binding:"required"`
	CompanyName *string `json:"company_name"`
	Email       string  `json:"email" binding:"required,email"`
	Phone       string  `json:"phone" binding:"required"`
	Password    string  `json:"password" binding:"required,min=8"`
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	user, err := h.authService.Register(c.Request.Context(), services.RegisterInput{
		Role:        models.UserRole(req.Role),
		FullName:    req.FullName,
		CompanyName: req.CompanyName,
		Email:       req.Email,
		Phone:       req.Phone,
		Password:    req.Password,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	response.Success(c, http.StatusCreated, gin.H{
		"user":    user,
		"message": "Registered successfully. KYC verification pending — complete KYC to start transacting.",
	})
}

type loginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
	// Role — optional; multi-role login lets the same account log in as importer, exporter,
	// or logistics regardless of which role it was registered/last logged-in under. Omitted
	// or empty = login as whatever role the account already has (previous behavior).
	Role string `json:"role" binding:"omitempty,oneof=importer exporter logistics"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	user, pair, err := h.authService.Login(c.Request.Context(), req.Email, req.Password, req.Role, security.ExtractRequestMeta(c))
	if err != nil {
		response.Error(c, http.StatusUnauthorized, err.Error())
		return
	}

	response.Success(c, http.StatusOK, gin.H{
		"user":          user,
		"access_token":  pair.AccessToken,
		"refresh_token": pair.RefreshToken,
	})
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// Refresh — exchanges a valid (unexpired, unrevoked) refresh token for a brand new
// access+refresh pair, rotating the old refresh token out.
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req refreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	pair, err := h.authService.RefreshTokens(c.Request.Context(), req.RefreshToken)
	if err != nil {
		response.Error(c, http.StatusUnauthorized, err.Error())
		return
	}

	response.Success(c, http.StatusOK, gin.H{
		"access_token":  pair.AccessToken,
		"refresh_token": pair.RefreshToken,
	})
}

// Logout — revokes the given refresh token so it can't be used to mint new access tokens.
func (h *AuthHandler) Logout(c *gin.Context) {
	var req refreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.authService.Logout(c.Request.Context(), req.RefreshToken); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "logged out"})
}

// LogoutAllDevices — revokes every refresh token belonging to the authenticated user (Part 1
// "Logout from All Devices"). Requires a valid access token, unlike the single-device Logout
// above which only needs the refresh token itself.
func (h *AuthHandler) LogoutAllDevices(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.authService.LogoutAllDevices(c.Request.Context(), userID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "logged out from all devices"})
}
