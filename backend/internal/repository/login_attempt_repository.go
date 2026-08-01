package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type LoginAttemptRepository struct {
	db *pgxpool.Pool
}

func NewLoginAttemptRepository(db *pgxpool.Pool) *LoginAttemptRepository {
	return &LoginAttemptRepository{db: db}
}

func (r *LoginAttemptRepository) Record(ctx context.Context, email string, success bool) error {
	_, err := r.db.Exec(ctx, `INSERT INTO login_attempts (email, success) VALUES ($1, $2)`, email, success)
	return err
}

// LoginAttemptMeta — the enriched request context recorded alongside every login attempt
// (Part 8/9: login history needs IP/device/country, not just success/failure).
type LoginAttemptMeta struct {
	UserID    *string // nil if the email didn't resolve to a real account
	IP        string
	DeviceID  string
	UserAgent string
	Country   string
}

func (r *LoginAttemptRepository) RecordWithMeta(ctx context.Context, email string, success bool, meta LoginAttemptMeta) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO login_attempts (email, success, ip_address, user_id, device_id, user_agent, country)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		email, success, meta.IP, meta.UserID, meta.DeviceID, meta.UserAgent, meta.Country)
	return err
}

// CountRecentFailures — failed attempts for this email within the last windowMinutes,
// used to enforce brute-force account lockout (Part 1).
func (r *LoginAttemptRepository) CountRecentFailures(ctx context.Context, email string, windowMinutes int) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM login_attempts
		WHERE email = $1 AND success = false AND created_at > now() - make_interval(mins => $2)`,
		email, windowMinutes).Scan(&count)
	return count, err
}

// RecentLoginHistory — for the Security Dashboard's "Login History" list (Part 12).
type LoginHistoryEntry struct {
	Success   bool
	IP        string
	DeviceID  *string
	UserAgent *string
	Country   *string
	CreatedAt time.Time
}

func (r *LoginAttemptRepository) RecentLoginHistory(ctx context.Context, userID string, limit int) ([]LoginHistoryEntry, error) {
	rows, err := r.db.Query(ctx, `
		SELECT success, COALESCE(ip_address, ''), device_id, user_agent, country, created_at
		FROM login_attempts WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []LoginHistoryEntry
	for rows.Next() {
		var e LoginHistoryEntry
		if err := rows.Scan(&e.Success, &e.IP, &e.DeviceID, &e.UserAgent, &e.Country, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// RecentFailedLoginEmails — emails with more than `threshold` failed attempts in the last hour.
func (r *LoginAttemptRepository) RecentFailedLoginEmails(ctx context.Context, threshold int) (map[string]int, error) {
	rows, err := r.db.Query(ctx, `
		SELECT email, COUNT(*) FROM login_attempts
		WHERE success = false AND created_at > now() - interval '1 hour'
		GROUP BY email HAVING COUNT(*) > $1`, threshold)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string]int)
	for rows.Next() {
		var email string
		var count int
		if err := rows.Scan(&email, &count); err != nil {
			return nil, err
		}
		out[email] = count
	}
	return out, nil
}
