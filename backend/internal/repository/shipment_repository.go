package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type ShipmentRepository struct {
	db *pgxpool.Pool
}

func NewShipmentRepository(db *pgxpool.Pool) *ShipmentRepository {
	return &ShipmentRepository{db: db}
}

func (r *ShipmentRepository) GetByOrderID(ctx context.Context, orderID string) (*models.Shipment, error) {
	query := `SELECT id, order_id, logistics_id, tracking_number, status, pickup_address,
		delivery_address, carrier_name, estimated_delivery, picked_up_at, delivered_at,
		created_at, updated_at FROM shipments WHERE order_id = $1`
	var s models.Shipment
	err := r.db.QueryRow(ctx, query, orderID).Scan(
		&s.ID, &s.OrderID, &s.LogisticsID, &s.TrackingNumber, &s.Status, &s.PickupAddress,
		&s.DeliveryAddress, &s.CarrierName, &s.EstimatedDelivery, &s.PickedUpAt, &s.DeliveredAt,
		&s.CreatedAt, &s.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &s, nil
}

func (r *ShipmentRepository) GetByID(ctx context.Context, shipmentID string) (*models.Shipment, error) {
	query := `SELECT id, order_id, logistics_id, tracking_number, status, pickup_address,
		delivery_address, carrier_name, estimated_delivery, picked_up_at, delivered_at,
		created_at, updated_at FROM shipments WHERE id = $1`
	var s models.Shipment
	err := r.db.QueryRow(ctx, query, shipmentID).Scan(
		&s.ID, &s.OrderID, &s.LogisticsID, &s.TrackingNumber, &s.Status, &s.PickupAddress,
		&s.DeliveryAddress, &s.CarrierName, &s.EstimatedDelivery, &s.PickedUpAt, &s.DeliveredAt,
		&s.CreatedAt, &s.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &s, nil
}

// AssignLogistics — exporter picks a 3PL partner for their order's shipment.
func (r *ShipmentRepository) AssignLogistics(ctx context.Context, orderID, logisticsID, trackingNumber, carrierName string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		UPDATE shipments SET logistics_id = $1, tracking_number = $2, carrier_name = $3, status = 'assigned'
		WHERE order_id = $4`, logisticsID, trackingNumber, carrierName, orderID)
	if err != nil {
		return fmt.Errorf("assign logistics: %w", err)
	}

	_, err = tx.Exec(ctx, `UPDATE orders SET status = 'shipped' WHERE id = $1`, orderID)
	if err != nil {
		return err
	}

	var shipmentID string
	if err := tx.QueryRow(ctx, `SELECT id FROM shipments WHERE order_id = $1`, orderID).Scan(&shipmentID); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO shipment_events (shipment_id, status, remarks) VALUES ($1, 'assigned', 'Assigned to 3PL partner')`, shipmentID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// UpdateStatus — logistics partner updates shipment progress (picked_up, in_transit, delivered).
func (r *ShipmentRepository) UpdateStatus(ctx context.Context, shipmentID, status, location, remarks string, updatedBy string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	timeCol := ""
	switch status {
	case "picked_up":
		timeCol = ", picked_up_at = now()"
	case "delivered":
		timeCol = ", delivered_at = now()"
	}

	// BUG FIX (C9): previously matched WHERE id = $2 only — updatedBy (the logistics user's own ID)
	// was recorded in shipment_events but never checked against the shipment's assigned
	// logistics_id, so any authenticated logistics-role user could update the status of ANY
	// shipment, not just ones assigned to them. Constraining the WHERE clause closes that.
	query := fmt.Sprintf(`UPDATE shipments SET status = $1%s WHERE id = $2 AND logistics_id = $3 RETURNING order_id`, timeCol)
	var orderID string
	if err := tx.QueryRow(ctx, query, status, shipmentID, updatedBy).Scan(&orderID); err != nil {
		return fmt.Errorf("update shipment status: shipment not found or not assigned to you: %w", err)
	}

	_, err = tx.Exec(ctx, `INSERT INTO shipment_events (shipment_id, status, location, remarks, created_by)
		VALUES ($1,$2,$3,$4,$5)`, shipmentID, status, location, remarks, updatedBy)
	if err != nil {
		return err
	}

	// Mirror key statuses onto the order for quick dashboard queries. The granular
	// in-between stages (pickup_scheduled, at_warehouse, customs_clearance, loaded,
	// arrived_at_destination, out_for_delivery) are shipment-level detail only — the
	// order stays "shipped" (set at assignment) until transit/delivery milestones.
	orderStatus := ""
	switch status {
	case "in_transit", "arrived_at_destination", "out_for_delivery":
		orderStatus = "in_transit"
	case "delivered":
		orderStatus = "delivered"
	}
	if orderStatus != "" {
		// BUG FIX (M-4): this UPDATE was unconditional — an order already at a terminal state
		// (payment_released, refunded, disputed) could be rolled back to in_transit/delivered by
		// a later shipment status update, corrupting the order state machine and the admin escrow
		// list. Escrow money itself was already protected by separate guards; this only guards
		// the order row's own status column.
		if _, err := tx.Exec(ctx, `UPDATE orders SET status = $1
			WHERE id = $2 AND status NOT IN ('payment_released', 'refunded', 'disputed')`, orderStatus, orderID); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

// IsAssignedWithParty — Journey 8: whether logisticsID is assigned to any shipment whose
// order's importer or exporter is otherUserID. Used to gate logistics<->importer/exporter
// chat to "joins only after assignment" instead of any logistics user being able to message
// any importer/exporter with no relationship.
func (r *ShipmentRepository) IsAssignedWithParty(ctx context.Context, logisticsID, otherUserID string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM shipments s
			JOIN orders o ON o.id = s.order_id
			WHERE s.logistics_id = $1 AND (o.importer_id = $2 OR o.exporter_id = $2)
		)`, logisticsID, otherUserID).Scan(&exists)
	return exists, err
}

func (r *ShipmentRepository) ListByLogistics(ctx context.Context, logisticsID string, limit, offset int) ([]models.Shipment, error) {
	query := `SELECT id, order_id, logistics_id, tracking_number, status, pickup_address,
		delivery_address, carrier_name, estimated_delivery, picked_up_at, delivered_at,
		created_at, updated_at FROM shipments WHERE logistics_id = $1
		ORDER BY created_at DESC LIMIT $2 OFFSET $3`

	rows, err := r.db.Query(ctx, query, logisticsID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var list []models.Shipment
	for rows.Next() {
		var s models.Shipment
		if err := rows.Scan(
			&s.ID, &s.OrderID, &s.LogisticsID, &s.TrackingNumber, &s.Status, &s.PickupAddress,
			&s.DeliveryAddress, &s.CarrierName, &s.EstimatedDelivery, &s.PickedUpAt, &s.DeliveredAt,
			&s.CreatedAt, &s.UpdatedAt,
		); err != nil {
			return nil, err
		}
		list = append(list, s)
	}
	return list, rows.Err()
}

func (r *ShipmentRepository) AddPOD(ctx context.Context, pod *models.PODDocument) error {
	query := `INSERT INTO pod_documents (shipment_id, uploaded_by, file_url, file_type, signature_url, remarks)
		VALUES ($1,$2,$3,$4,$5,$6) RETURNING id, created_at`
	return r.db.QueryRow(ctx, query, pod.ShipmentID, pod.UploadedBy, pod.FileURL, pod.FileType,
		pod.SignatureURL, pod.Remarks).Scan(&pod.ID, &pod.CreatedAt)
}

func (r *ShipmentRepository) GetEvents(ctx context.Context, shipmentID string) ([]models.ShipmentEvent, error) {
	query := `SELECT id, shipment_id, status, location, remarks, created_by, created_at
		FROM shipment_events WHERE shipment_id = $1 ORDER BY created_at ASC`
	rows, err := r.db.Query(ctx, query, shipmentID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []models.ShipmentEvent
	for rows.Next() {
		var e models.ShipmentEvent
		if err := rows.Scan(&e.ID, &e.ShipmentID, &e.Status, &e.Location, &e.Remarks, &e.CreatedBy, &e.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	return events, rows.Err()
}
