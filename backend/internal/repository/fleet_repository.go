package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type FleetRepository struct {
	db *pgxpool.Pool
}

func NewFleetRepository(db *pgxpool.Pool) *FleetRepository {
	return &FleetRepository{db: db}
}

func (r *FleetRepository) Create(ctx context.Context, v *models.FleetVehicle) error {
	query := `INSERT INTO fleet_vehicles (logistics_id, vehicle_type, registration_number, capacity_kg, capacity_cbm, service_route, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query,
		v.LogisticsID, v.VehicleType, v.RegistrationNumber, v.CapacityKg, v.CapacityCBM, v.ServiceRoute, v.Status,
	).Scan(&v.ID, &v.CreatedAt, &v.UpdatedAt)
}

func (r *FleetRepository) ListByLogistics(ctx context.Context, logisticsID string) ([]models.FleetVehicle, error) {
	query := `SELECT id, logistics_id, vehicle_type, registration_number, capacity_kg, capacity_cbm, service_route, status, created_at, updated_at
		FROM fleet_vehicles WHERE logistics_id = $1 ORDER BY created_at DESC`
	rows, err := r.db.Query(ctx, query, logisticsID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.FleetVehicle
	for rows.Next() {
		var v models.FleetVehicle
		if err := rows.Scan(&v.ID, &v.LogisticsID, &v.VehicleType, &v.RegistrationNumber, &v.CapacityKg, &v.CapacityCBM, &v.ServiceRoute, &v.Status, &v.CreatedAt, &v.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (r *FleetRepository) GetByID(ctx context.Context, id string) (*models.FleetVehicle, error) {
	query := `SELECT id, logistics_id, vehicle_type, registration_number, capacity_kg, capacity_cbm, service_route, status, created_at, updated_at
		FROM fleet_vehicles WHERE id = $1`
	var v models.FleetVehicle
	err := r.db.QueryRow(ctx, query, id).Scan(&v.ID, &v.LogisticsID, &v.VehicleType, &v.RegistrationNumber, &v.CapacityKg, &v.CapacityCBM, &v.ServiceRoute, &v.Status, &v.CreatedAt, &v.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("vehicle not found")
		}
		return nil, err
	}
	return &v, nil
}

func (r *FleetRepository) Update(ctx context.Context, v *models.FleetVehicle) error {
	query := `UPDATE fleet_vehicles SET vehicle_type=$1, registration_number=$2, capacity_kg=$3, capacity_cbm=$4, service_route=$5, status=$6
		WHERE id = $7 AND logistics_id = $8`
	tag, err := r.db.Exec(ctx, query, v.VehicleType, v.RegistrationNumber, v.CapacityKg, v.CapacityCBM, v.ServiceRoute, v.Status, v.ID, v.LogisticsID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("vehicle not found or not owned by this logistics partner")
	}
	return nil
}

func (r *FleetRepository) Delete(ctx context.Context, id, logisticsID string) error {
	tag, err := r.db.Exec(ctx, `DELETE FROM fleet_vehicles WHERE id = $1 AND logistics_id = $2`, id, logisticsID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("vehicle not found or not owned by this logistics partner")
	}
	return nil
}
