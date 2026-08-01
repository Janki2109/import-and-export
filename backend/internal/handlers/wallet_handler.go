package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type WalletHandler struct {
	walletService *services.WalletService
}

func NewWalletHandler(walletService *services.WalletService) *WalletHandler {
	return &WalletHandler{walletService: walletService}
}

// GetMyWallet — balance + recent ledger transactions for the logged-in user (exporter/logistics/importer).
func (h *WalletHandler) GetMyWallet(c *gin.Context) {
	userID := c.GetString("user_id")
	summary, err := h.walletService.GetSummary(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, summary)
}

type withdrawRequest struct {
	Amount float64 `json:"amount" binding:"required,gt=0"`
}

// Withdraw — pays out wallet balance to the user's linked bank/UPI fund account.
func (h *WalletHandler) Withdraw(c *gin.Context) {
	userID := c.GetString("user_id")
	var req withdrawRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.walletService.Withdraw(c.Request.Context(), userID, req.Amount); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "withdrawal initiated"})
}
