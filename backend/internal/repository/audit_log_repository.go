package repository

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type AuditLogRepository struct {
	db *pgxpool.Pool
}

func NewAuditLogRepository(db *pgxpool.Pool) *AuditLogRepository {
	return &AuditLogRepository{db: db}
}

// Record — fire-and-forget style: callers log the action after it succeeds. metadata is
// any JSON-serializable extra context (e.g. {"reason": "..."} for a rejection).
func (r *AuditLogRepository) Record(ctx context.Context, actorID, action, entityType, entityID string, metadata map[string]interface{}) error {
	var metaJSON []byte
	if metadata != nil {
		var err error
		metaJSON, err = json.Marshal(metadata)
		if err != nil {
			return err
		}
	}
	_, err := r.db.Exec(ctx,
		`INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata) VALUES ($1,$2,$3,$4,$5)`,
		nullableID(actorID), action, entityType, nullableID(entityID), metaJSON)
	return err
}

func nullableID(id string) *string {
	if id == "" {
		return nil
	}
	return &id
}

// ListByEntity — audit trail for one specific entity (e.g. entityType="escrow",
// entityID=orderID) — powers the "Escrow History" view on an order.
func (r *AuditLogRepository) ListByEntity(ctx context.Context, entityType, entityID string, limit, offset int) ([]models.AuditLog, error) {
	query := `SELECT id, actor_id, action, entity_type, entity_id, metadata, created_at
		FROM audit_logs WHERE entity_type = $1 AND entity_id = $2 ORDER BY created_at ASC LIMIT $3 OFFSET $4`
	rows, err := r.db.Query(ctx, query, entityType, entityID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.AuditLog
	for rows.Next() {
		var a models.AuditLog
		if err := rows.Scan(&a.ID, &a.ActorID, &a.Action, &a.EntityType, &a.EntityID, &a.Metadata, &a.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (r *AuditLogRepository) List(ctx context.Context, limit, offset int) ([]models.AuditLog, error) {
	query := `SELECT id, actor_id, action, entity_type, entity_id, metadata, created_at
		FROM audit_logs ORDER BY created_at DESC LIMIT $1 OFFSET $2`
	rows, err := r.db.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.AuditLog
	for rows.Next() {
		var a models.AuditLog
		if err := rows.Scan(&a.ID, &a.ActorID, &a.Action, &a.EntityType, &a.EntityID, &a.Metadata, &a.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}
