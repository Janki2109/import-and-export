package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type NotificationHandler struct {
	svc *services.NotificationService
}

func NewNotificationHandler(svc *services.NotificationService) *NotificationHandler {
	return &NotificationHandler{svc: svc}
}

func (h *NotificationHandler) List(c *gin.Context) {
	userID := c.GetString("user_id")
	list, err := h.svc.List(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, list)
}

func (h *NotificationHandler) MarkRead(c *gin.Context) {
	userID := c.GetString("user_id")
	id := c.Param("id")
	if err := h.svc.MarkRead(c.Request.Context(), id, userID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "marked as read"})
}

type registerDeviceRequest struct {
	Token    string `json:"token" binding:"required"`
	Platform string `json:"platform" binding:"required,oneof=android ios"`
}

// RegisterDevice — Flutter calls this right after login with its FCM registration token.
func (h *NotificationHandler) RegisterDevice(c *gin.Context) {
	userID := c.GetString("user_id")
	var req registerDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.svc.RegisterDevice(c.Request.Context(), userID, req.Token, req.Platform); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "device registered"})
}

type unregisterDeviceRequest struct {
	Token string `json:"token" binding:"required"`
}

// UnregisterDevice — Flutter calls this on logout so this device stops receiving pushes for
// the account that just signed out (important on shared/reused devices).
func (h *NotificationHandler) UnregisterDevice(c *gin.Context) {
	var req unregisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.svc.UnregisterDevice(c.Request.Context(), req.Token); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "device unregistered"})
}
