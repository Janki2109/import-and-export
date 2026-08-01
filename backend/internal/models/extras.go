package models

import "time"

type ShipmentEvent struct {
	ID        string    `json:"id" db:"id"`
	ShipmentID string   `json:"shipment_id" db:"shipment_id"`
	Status    string    `json:"status" db:"status"`
	Location  *string   `json:"location,omitempty" db:"location"`
	Remarks   *string   `json:"remarks,omitempty" db:"remarks"`
	CreatedBy *string   `json:"created_by,omitempty" db:"created_by"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}

type Dispute struct {
	ID               string     `json:"id" db:"id"`
	OrderID          string     `json:"order_id" db:"order_id"`
	RaisedBy         string     `json:"raised_by" db:"raised_by"`
	Reason           string     `json:"reason" db:"reason"`
	Status           string     `json:"status" db:"status"`
	ResolutionNotes  *string    `json:"resolution_notes,omitempty" db:"resolution_notes"`
	ResolvedBy       *string    `json:"resolved_by,omitempty" db:"resolved_by"`
	ResolvedAt       *time.Time `json:"resolved_at,omitempty" db:"resolved_at"`
	CreatedAt        time.Time  `json:"created_at" db:"created_at"`
}

type Notification struct {
	ID          string    `json:"id" db:"id"`
	UserID      string    `json:"user_id" db:"user_id"`
	Title       string    `json:"title" db:"title"`
	Body        string    `json:"body" db:"body"`
	Type        string    `json:"type" db:"type"`
	ReferenceID *string   `json:"reference_id,omitempty" db:"reference_id"`
	IsRead      bool      `json:"is_read" db:"is_read"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}
