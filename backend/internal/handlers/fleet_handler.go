package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/services"
	"github.com/jayashri-infotech/onebharat-backend/pkg/response"
)

type FleetHandler struct {
	fleetService *services.FleetService
}

func NewFleetHandler(fleetService *services.FleetService) *FleetHandler {
	return &FleetHandler{fleetService: fleetService}
}

type upsertVehicleRequest struct {
	VehicleType        string   `json:"vehicle_type" binding:"required"`
	RegistrationNumber string   `json:"registration_number" binding:"required"`
	CapacityKg         *float64 `json:"capacity_kg"`
	CapacityCBM        *float64 `json:"capacity_cbm"`
	ServiceRoute       *string  `json:"service_route"`
	Status             string   `json:"status"`
}

func (h *FleetHandler) Create(c *gin.Context) {
	logisticsID := c.GetString("user_id")
	var req upsertVehicleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	vehicle, err := h.fleetService.Create(c.Request.Context(), services.UpsertVehicleInput{
		LogisticsID: logisticsID, VehicleType: req.VehicleType, RegistrationNumber: req.RegistrationNumber,
		CapacityKg: req.CapacityKg, CapacityCBM: req.CapacityCBM, ServiceRoute: req.ServiceRoute,
		Status: models.VehicleStatus(req.Status),
	})
	if err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusCreated, vehicle)
}

func (h *FleetHandler) ListMine(c *gin.Context) {
	logisticsID := c.GetString("user_id")
	vehicles, err := h.fleetService.ListMine(c.Request.Context(), logisticsID)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, err.Error())
		return
	}
	response.Success(c, http.StatusOK, vehicles)
}

func (h *FleetHandler) Update(c *gin.Context) {
	logisticsID := c.GetString("user_id")
	id := c.Param("id")
	var req upsertVehicleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.fleetService.Update(c.Request.Context(), id, services.UpsertVehicleInput{
		LogisticsID: logisticsID, VehicleType: req.VehicleType, RegistrationNumber: req.RegistrationNumber,
		CapacityKg: req.CapacityKg, CapacityCBM: req.CapacityCBM, ServiceRoute: req.ServiceRoute,
		Status: models.VehicleStatus(req.Status),
	}); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "vehicle updated"})
}

func (h *FleetHandler) Delete(c *gin.Context) {
	logisticsID := c.GetString("user_id")
	id := c.Param("id")
	if err := h.fleetService.Delete(c.Request.Context(), id, logisticsID); err != nil {
		response.Error(c, http.StatusBadRequest, err.Error())
		return
	}
	response.Success(c, http.StatusOK, gin.H{"message": "vehicle removed"})
}
