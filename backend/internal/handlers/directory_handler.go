package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type DirectoryHandler struct {
	directoryService *services.DirectoryService
}

func NewDirectoryHandler(directoryService *services.DirectoryService) *DirectoryHandler {
	return &DirectoryHandler{directoryService: directoryService}
}

// ListLogisticsPartners — "Find Logistics Partner": browse active logistics companies,
// optionally filtered by name/company/city/country via ?q=.
func (h *DirectoryHandler) ListLogisticsPartners(c *gin.Context) {
	partners, err := h.directoryService.ListLogisticsPartners(c.Request.Context(), c.Query("q"))
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, partners)
}
