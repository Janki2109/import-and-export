package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type RefreshTokenRepository struct {
	db *pgxpool.Pool
}

func NewRefreshTokenRepository(db *pgxpool.Pool) *RefreshTokenRepository {
	return &RefreshTokenRepository{db: db}
}

func (r *RefreshTokenRepository) Create(ctx context.Context, userID, tokenHash string, expiresAt time.Time) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		userID, tokenHash, expiresAt)
	return err
}

// GetValidByHash returns the user_id for a non-revoked, non-expired token hash, or "" if not found/invalid.
func (r *RefreshTokenRepository) GetValidByHash(ctx context.Context, tokenHash string) (string, error) {
	var userID string
	err := r.db.QueryRow(ctx,
		`SELECT user_id FROM refresh_tokens
		 WHERE token_hash = $1 AND revoked = false AND expires_at > now()`,
		tokenHash,
	).Scan(&userID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", nil
		}
		return "", err
	}
	return userID, nil
}

func (r *RefreshTokenRepository) RevokeByHash(ctx context.Context, tokenHash string) error {
	_, err := r.db.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE token_hash = $1`, tokenHash)
	return err
}

// RevokeIfValid — SECURITY FIX (H-05): makes rotation atomic by using the revocation itself as
// the gate (UPDATE ... WHERE revoked = false AND expires_at > now() RETURNING user_id) instead
// of a separate GetValidByHash-then-RevokeByHash pair. Two concurrent refreshes with the same
// token can no longer both read "still valid" before either write lands — only the first one to
// commit the UPDATE gets a non-empty userID back; the second sees zero rows affected and fails.
// Returns ("", nil) if the token was already revoked/expired/unknown (indistinguishable, by
// design — same as the old GetValidByHash contract).
func (r *RefreshTokenRepository) RevokeIfValid(ctx context.Context, tokenHash string) (string, error) {
	var userID string
	err := r.db.QueryRow(ctx,
		`UPDATE refresh_tokens SET revoked = true
		 WHERE token_hash = $1 AND revoked = false AND expires_at > now()
		 RETURNING user_id`,
		tokenHash,
	).Scan(&userID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", nil
		}
		return "", err
	}
	return userID, nil
}

// WasIssued reports whether a token hash exists at all (regardless of revoked/expired state) —
// used to distinguish "never existed" from "existed but already revoked", the latter being the
// canonical signal of token theft (see M-03: reuse detection).
func (r *RefreshTokenRepository) WasIssued(ctx context.Context, tokenHash string) (string, bool, error) {
	var userID string
	err := r.db.QueryRow(ctx, `SELECT user_id FROM refresh_tokens WHERE token_hash = $1`, tokenHash).Scan(&userID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", false, nil
		}
		return "", false, err
	}
	return userID, true, nil
}

func (r *RefreshTokenRepository) RevokeAllForUser(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE user_id = $1`, userID)
	return err
}
