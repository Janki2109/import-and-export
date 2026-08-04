package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(ctx context.Context, u *models.User) error {
	query := `INSERT INTO users (role, full_name, company_name, email, phone, password_hash)
		VALUES ($1,$2,$3,$4,$5,$6)
		RETURNING id, is_active, is_email_verified, is_phone_verified, created_at, updated_at`
	return r.db.QueryRow(ctx, query, u.Role, u.FullName, u.CompanyName, u.Email, u.Phone, u.PasswordHash).
		Scan(&u.ID, &u.IsActive, &u.IsEmailVerified, &u.IsPhoneVerified, &u.CreatedAt, &u.UpdatedAt)
}

// ListByRole — every active user with the given role (nil = every role), for the admin
// Notification Management broadcast feature.
func (r *UserRepository) ListByRole(ctx context.Context, role *string) ([]models.User, error) {
	query := `SELECT id, role, full_name, company_name, email, phone, is_active, created_at, updated_at
		FROM users WHERE is_active = true AND ($1::text IS NULL OR role = $1::user_role)`
	rows, err := r.db.Query(ctx, query, role)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.User
	for rows.Next() {
		var u models.User
		if err := rows.Scan(&u.ID, &u.Role, &u.FullName, &u.CompanyName, &u.Email, &u.Phone, &u.IsActive, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, nil
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*models.User, error) {
	query := `SELECT id, role, full_name, company_name, email, phone, avatar_url, password_hash,
		is_active, is_email_verified, is_phone_verified, razorpay_contact_id,
		razorpay_fund_account_id, created_at, updated_at
		FROM users WHERE email = $1`
	var u models.User
	err := r.db.QueryRow(ctx, query, email).Scan(
		&u.ID, &u.Role, &u.FullName, &u.CompanyName, &u.Email, &u.Phone, &u.AvatarURL, &u.PasswordHash,
		&u.IsActive, &u.IsEmailVerified, &u.IsPhoneVerified, &u.RazorpayContactID,
		&u.RazorpayFundAccountID, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

// SetRazorpayLinkage stores the Route contact_id + fund_account_id once created (post KYC-approval),
// so future payouts to this user (exporter/logistics) can reference them directly.
func (r *UserRepository) SetRazorpayLinkage(ctx context.Context, userID, contactID, fundAccountID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET razorpay_contact_id = $1, razorpay_fund_account_id = $2 WHERE id = $3`,
		contactID, fundAccountID, userID)
	return err
}

// SetChatPublicKey — Journey 11 "end-to-end encrypted chat": publishes this user's X25519
// public key so any other user can derive a shared ECDH secret with them, entirely
// client-side. The server never sees a private key.
func (r *UserRepository) SetChatPublicKey(ctx context.Context, userID, publicKey string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET chat_public_key = $1 WHERE id = $2`, publicKey, userID)
	return err
}

// GetFirstAdmin returns the oldest admin account — used to resolve a "contact support"
// conversation target without the user needing to know an admin's user ID.
func (r *UserRepository) GetFirstAdmin(ctx context.Context) (*models.User, error) {
	query := `SELECT id, role, full_name, company_name, email, phone, avatar_url, password_hash,
		is_active, is_email_verified, is_phone_verified, razorpay_contact_id,
		razorpay_fund_account_id, created_at, updated_at
		FROM users WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1`
	var u models.User
	err := r.db.QueryRow(ctx, query).Scan(
		&u.ID, &u.Role, &u.FullName, &u.CompanyName, &u.Email, &u.Phone, &u.AvatarURL, &u.PasswordHash,
		&u.IsActive, &u.IsEmailVerified, &u.IsPhoneVerified, &u.RazorpayContactID,
		&u.RazorpayFundAccountID, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

func (r *UserRepository) GetByID(ctx context.Context, id string) (*models.User, error) {
	query := `SELECT id, role, full_name, company_name, email, phone, avatar_url, password_hash,
		is_active, is_email_verified, is_phone_verified, razorpay_contact_id,
		razorpay_fund_account_id, chat_public_key, created_at, updated_at
		FROM users WHERE id = $1`
	var u models.User
	err := r.db.QueryRow(ctx, query, id).Scan(
		&u.ID, &u.Role, &u.FullName, &u.CompanyName, &u.Email, &u.Phone, &u.AvatarURL, &u.PasswordHash,
		&u.IsActive, &u.IsEmailVerified, &u.IsPhoneVerified, &u.RazorpayContactID,
		&u.RazorpayFundAccountID, &u.ChatPublicKey, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

// UpdateProfile — the Profile module's own update path, separate from anything auth-related
// (password, role, verification flags are all untouched here).
func (r *UserRepository) UpdateProfile(ctx context.Context, userID, fullName, email, phone string, avatarURL *string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET full_name = $1, email = $2, phone = $3, avatar_url = $4 WHERE id = $5`,
		fullName, email, phone, avatarURL, userID)
	return err
}

// UpdatePasswordHash — used by the Profile module's "Change Password" action.
func (r *UserRepository) UpdatePasswordHash(ctx context.Context, userID, passwordHash string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET password_hash = $1 WHERE id = $2`, passwordHash, userID)
	return err
}

// FlagAccount — marks an account as flagged for admin review (Part 7's fraud detection
// output). Does not deactivate/restrict the account itself — flagging is a review signal,
// not an automatic punishment.
func (r *UserRepository) FlagAccount(ctx context.Context, userID, reason string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET is_flagged = true, flagged_reason = $1, flagged_at = now() WHERE id = $2`, reason, userID)
	return err
}
