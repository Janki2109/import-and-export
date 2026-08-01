package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type APIKeyHandler struct {
	apiKeyService *services.APIKeyService
}

func NewAPIKeyHandler(apiKeyService *services.APIKeyService) *APIKeyHandler {
	return &APIKeyHandler{apiKeyService: apiKeyService}
}

type generateAPIKeyRequest struct {
	Label *string `json:"label"`
}

// Generate — Enterprise-tier only. Returns the raw key exactly once; only its hash is stored.
func (h *APIKeyHandler) Generate(c *gin.Context) {
	userID := c.GetString("user_id")
	var req generateAPIKeyRequest
	_ = c.ShouldBindJSON(&req)

	rawKey, key, err := h.apiKeyService.Generate(c.Request.Context(), userID, req.Label)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, gin.H{
		"api_key": rawKey,
		"id":      key.ID,
		"message": "Save this key now — it will not be shown again.",
	})
}

func (h *APIKeyHandler) ListMine(c *gin.Context) {
	userID := c.GetString("user_id")
	keys, err := h.apiKeyService.ListMine(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, keys)
}

func (h *APIKeyHandler) Revoke(c *gin.Context) {
	userID := c.GetString("user_id")
	if err := h.apiKeyService.Revoke(c.Request.Context(), c.Param("id"), userID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "API key revoked"})
}
