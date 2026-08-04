package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type ShipmentHandler struct {
	shipmentService *services.ShipmentService
}

func NewShipmentHandler(shipmentService *services.ShipmentService) *ShipmentHandler {
	return &ShipmentHandler{shipmentService: shipmentService}
}

type assignLogisticsRequest struct {
	OrderID        string `json:"order_id" binding:"required"`
	LogisticsID    string `json:"logistics_id" binding:"required"`
	TrackingNumber string `json:"tracking_number" binding:"required"`
	CarrierName    string `json:"carrier_name" binding:"required"`
}

// AssignLogistics — exporter picks a 3PL for the shipment.
func (h *ShipmentHandler) AssignLogistics(c *gin.Context) {
	exporterID := c.GetString("user_id")
	var req assignLogisticsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.shipmentService.AssignLogistics(c.Request.Context(), req.OrderID, exporterID, req.LogisticsID, req.TrackingNumber, req.CarrierName); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "Logistics partner assigned, order marked as shipped."})
}

type updateStatusRequest struct {
	ShipmentID string `json:"shipment_id" binding:"required"`
	Status     string `json:"status" binding:"required"`
	Location   string `json:"location"`
	Remarks    string `json:"remarks"`
}

// UpdateStatus — 3PL updates: picked_up / in_transit / delivered / exception.
func (h *ShipmentHandler) UpdateStatus(c *gin.Context) {
	logisticsID := c.GetString("user_id")
	var req updateStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	if err := h.shipmentService.UpdateShipmentStatus(c.Request.Context(), req.ShipmentID, logisticsID, req.Status, req.Location, req.Remarks); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "Shipment status updated: " + req.Status})
}

type uploadPODRequest struct {
	ShipmentID   string  `json:"shipment_id" binding:"required"`
	FileURL      string  `json:"file_url" binding:"required"`
	FileType     string  `json:"file_type"`
	SignatureURL *string `json:"signature_url"`
	Remarks      *string `json:"remarks"`
}

// UploadPOD — 3PL uploads proof of delivery (photo/signature) at drop-off.
func (h *ShipmentHandler) UploadPOD(c *gin.Context) {
	userID := c.GetString("user_id")
	var req uploadPODRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	fileType := req.FileType
	if fileType == "" {
		fileType = "image"
	}
	pod := &models.PODDocument{
		ShipmentID: req.ShipmentID, UploadedBy: userID, FileURL: req.FileURL,
		FileType: fileType, SignatureURL: req.SignatureURL, Remarks: req.Remarks,
	}
	if err := h.shipmentService.UploadPOD(c.Request.Context(), pod); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "POD uploaded", "pod": pod})
}

func (h *ShipmentHandler) GetByOrder(c *gin.Context) {
	orderID := c.Param("order_id")
	userID := c.GetString("user_id")
	role := c.GetString("role")
	shipment, err := h.shipmentService.GetByOrderID(c.Request.Context(), orderID, userID, role)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, shipment)
}

func (h *ShipmentHandler) GetTimeline(c *gin.Context) {
	shipmentID := c.Param("shipment_id")
	userID := c.GetString("user_id")
	role := c.GetString("role")
	events, err := h.shipmentService.GetTrackingTimeline(c.Request.Context(), shipmentID, userID, role)
	if err != nil {
		response.Error(c, http.StatusForbidden, err.Error())
		return
	}
	response.Success(c, http.StatusOK, events)
}

func (h *ShipmentHandler) ListMine(c *gin.Context) {
	logisticsID := c.GetString("user_id")
	list, err := h.shipmentService.ListMyShipments(c.Request.Context(), logisticsID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, list)
}
