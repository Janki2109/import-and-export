package services

import (
	"context"

	"github.com/jayashri-infotech/onebharat-backend/internal/models"
	"github.com/jayashri-infotech/onebharat-backend/internal/repository"
)

type FleetService struct {
	repo *repository.FleetRepository
}

func NewFleetService(repo *repository.FleetRepository) *FleetService {
	return &FleetService{repo: repo}
}

type UpsertVehicleInput struct {
	LogisticsID        string
	VehicleType        string
	RegistrationNumber string
	CapacityKg         *float64
	CapacityCBM        *float64
	ServiceRoute       *string
	Status             models.VehicleStatus
}

func (s *FleetService) Create(ctx context.Context, in UpsertVehicleInput) (*models.FleetVehicle, error) {
	status := in.Status
	if status == "" {
		status = models.VehicleActive
	}
	v := &models.FleetVehicle{
		LogisticsID:        in.LogisticsID,
		VehicleType:        in.VehicleType,
		RegistrationNumber: in.RegistrationNumber,
		CapacityKg:         in.CapacityKg,
		CapacityCBM:        in.CapacityCBM,
		ServiceRoute:       in.ServiceRoute,
		Status:             status,
	}
	if err := s.repo.Create(ctx, v); err != nil {
		return nil, err
	}
	return v, nil
}

func (s *FleetService) ListMine(ctx context.Context, logisticsID string) ([]models.FleetVehicle, error) {
	return s.repo.ListByLogistics(ctx, logisticsID)
}

func (s *FleetService) Update(ctx context.Context, id string, in UpsertVehicleInput) error {
	// BUG FIX (H-19): Create defaults an empty status to VehicleActive; Update previously did
	// not, and status has no binding tag — any PUT /fleet/:id omitting "status" (e.g. a partner
	// just fixing a registration-number typo) executed SET status='' against the vehicle_status
	// NOT NULL/enum column, which Postgres rejected outright, so registration-number/capacity
	// edits could never be saved without also re-specifying a valid status.
	status := in.Status
	if status == "" {
		status = models.VehicleActive
	}
	v := &models.FleetVehicle{
		ID:                 id,
		LogisticsID:        in.LogisticsID,
		VehicleType:        in.VehicleType,
		RegistrationNumber: in.RegistrationNumber,
		CapacityKg:         in.CapacityKg,
		CapacityCBM:        in.CapacityCBM,
		ServiceRoute:       in.ServiceRoute,
		Status:             status,
	}
	return s.repo.Update(ctx, v)
}

func (s *FleetService) Delete(ctx context.Context, id, logisticsID string) error {
	return s.repo.Delete(ctx, id, logisticsID)
}
