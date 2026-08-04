package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type SecurityFlag struct {
	ID          string    `json:"id"`
	UserID      *string   `json:"user_id,omitempty"`
	Rule        string    `json:"rule"`
	Severity    string    `json:"severity"`
	Description string    `json:"description"`
	Resolved    bool      `json:"resolved"`
	CreatedAt   time.Time `json:"created_at"`
}

// SecurityFlagRepository persists FraudService's findings (Part 7/8) so they survive past a
// single admin-dashboard page load and can be reviewed/resolved over time.
type SecurityFlagRepository struct {
	db *pgxpool.Pool
}

func NewSecurityFlagRepository(db *pgxpool.Pool) *SecurityFlagRepository {
	return &SecurityFlagRepository{db: db}
}

func (r *SecurityFlagRepository) Create(ctx context.Context, userID *string, rule, severity, description string) error {
	_, err := r.db.Exec(ctx, `INSERT INTO security_flags (user_id, rule, severity, description) VALUES ($1, $2, $3, $4)`,
		userID, rule, severity, description)
	return err
}

// ExistsUnresolved — avoids re-flagging (and re-notifying admin about) the same rule for the
// same user every time the fraud sweep runs while the previous flag is still unresolved.
func (r *SecurityFlagRepository) ExistsUnresolved(ctx context.Context, userID, rule string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM security_flags WHERE user_id = $1 AND rule = $2 AND resolved = false)`, userID, rule).Scan(&exists)
	return exists, err
}

func (r *SecurityFlagRepository) List(ctx context.Context, resolvedFilter *bool, limit int) ([]SecurityFlag, error) {
	query := `SELECT id, user_id, rule, severity, description, resolved, created_at FROM security_flags WHERE ($1::boolean IS NULL OR resolved = $1) ORDER BY created_at DESC LIMIT $2`
	rows, err := r.db.Query(ctx, query, resolvedFilter, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []SecurityFlag
	for rows.Next() {
		var f SecurityFlag
		if err := rows.Scan(&f.ID, &f.UserID, &f.Rule, &f.Severity, &f.Description, &f.Resolved, &f.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

func (r *SecurityFlagRepository) GetByID(ctx context.Context, id string) (*SecurityFlag, error) {
	var f SecurityFlag
	err := r.db.QueryRow(ctx, `SELECT id, user_id, rule, severity, description, resolved, created_at FROM security_flags WHERE id = $1`, id).
		Scan(&f.ID, &f.UserID, &f.Rule, &f.Severity, &f.Description, &f.Resolved, &f.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &f, nil
}

func (r *SecurityFlagRepository) Resolve(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `UPDATE security_flags SET resolved = true WHERE id = $1`, id)
	return err
}
