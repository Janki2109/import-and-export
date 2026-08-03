package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type KYCHandler struct {
	kycService *services.KYCService
}

func NewKYCHandler(kycService *services.KYCService) *KYCHandler {
	return &KYCHandler{kycService: kycService}
}

type submitKYCRequest struct {
	PANNumber             *string `json:"pan_number"`
	GSTNumber             *string `json:"gst_number"`
	IECCode               *string `json:"iec_code"`
	BusinessLicense       *string `json:"business_license"`
	PANDocURL             *string `json:"pan_doc_url"`
	GSTDocURL             *string `json:"gst_doc_url"`
	IECDocURL             *string `json:"iec_doc_url"`
	AddressDocURL         *string `json:"address_doc_url"`
	BankAccountHolderName *string `json:"bank_account_holder_name"`
	BankAccountNumber     *string `json:"bank_account_number"`
	BankIFSC              *string `json:"bank_ifsc"`
}

// Submit — expects doc URLs already uploaded to S3 by the client (Flutter uploads directly
// via a presigned URL, then sends the final S3 URL here). Keeps this API lightweight.
func (h *KYCHandler) Submit(c *gin.Context) {
	userID := c.GetString("user_id")
	var req submitKYCRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	kyc, err := h.kycService.Submit(c.Request.Context(), services.SubmitKYCInput{
		UserID: userID, PANNumber: req.PANNumber, GSTNumber: req.GSTNumber, IECCode: req.IECCode,
		BusinessLicense: req.BusinessLicense, PANDocURL: req.PANDocURL, GSTDocURL: req.GSTDocURL,
		IECDocURL: req.IECDocURL, AddressDocURL: req.AddressDocURL,
		BankAccountHolderName: req.BankAccountHolderName, BankAccountNumber: req.BankAccountNumber, BankIFSC: req.BankIFSC,
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"kyc": kyc, "message": "KYC submitted, pending admin review."})
}

func (h *KYCHandler) GetMyStatus(c *gin.Context) {
	userID := c.GetString("user_id")
	kyc, err := h.kycService.GetStatus(c.Request.Context(), userID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	if kyc == nil {
		response.Success(c, http.StatusOK, gin.H{"status": "pending", "message": "KYC not yet submitted."})
		return
	}
	response.Success(c, http.StatusOK, kyc)
}

// ---- Admin ----

func (h *KYCHandler) ListPending(c *gin.Context) {
	list, err := h.kycService.ListPending(c.Request.Context(), 50, 0)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, list)
}

type approveRejectRequest struct {
	UserID string `json:"user_id" binding:"required"`
	Reason string `json:"reason"` // required for reject
}

func (h *KYCHandler) Approve(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req approveRejectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.kycService.Approve(c.Request.Context(), req.UserID, adminID); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "KYC approved"})
}

func (h *KYCHandler) Reject(c *gin.Context) {
	adminID := c.GetString("user_id")
	var req approveRejectRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.Reason == "" {
		response.Error(c, http.StatusBadRequest, "reason is required to reject KYC")
		return
	}
	if err := h.kycService.Reject(c.Request.Context(), req.UserID, adminID, req.Reason); err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "KYC rejected"})
}
