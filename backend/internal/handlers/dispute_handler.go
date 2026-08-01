package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type DisputeHandler struct {
	disputeService *services.DisputeService
}

func NewDisputeHandler(disputeService *services.DisputeService) *DisputeHandler {
	return &DisputeHandler{disputeService: disputeService}
}

type raiseDisputeRequest struct {
	OrderID string `json:"order_id" binding:"required"`
	Reason  string `json:"reason" binding:"required"`
}

// Raise — importer or exporter flags a problem with an order, freezing its escrow until admin review.
func (h *DisputeHandler) Raise(c *gin.Context) {
	userID := c.GetString("user_id")
	var req raiseDisputeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	dispute, err := h.disputeService.Raise(c.Request.Context(), req.OrderID, userID, req.Reason)
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, dispute)
}

func (h *DisputeHandler) ListMine(c *gin.Context) {
	userID := c.GetString("user_id")
	disputes, err := h.disputeService.ListMine(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, disputes)
}

// ListOpen — admin only, the review queue.
func (h *DisputeHandler) ListOpen(c *gin.Context) {
	disputes, err := h.disputeService.ListOpen(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, disputes)
}

type resolveDisputeRequest struct {
	Resolution string `json:"resolution" binding:"required,oneof=refund release"`
	Notes      string `json:"notes" binding:"required"`
}

// Resolve — admin only. "refund" returns escrow to the importer; "release" pays the exporter.
func (h *DisputeHandler) Resolve(c *gin.Context) {
	adminID := c.GetString("user_id")
	disputeID := c.Param("id")

	var req resolveDisputeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.disputeService.Resolve(c.Request.Context(), disputeID, adminID, req.Resolution, req.Notes); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "dispute resolved: " + req.Resolution})
}
