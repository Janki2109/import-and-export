package repository

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jayashri-infotech/onebharat-backend/internal/models"
)

type MembershipRepository struct {
	db *pgxpool.Pool
}

func NewMembershipRepository(db *pgxpool.Pool) *MembershipRepository {
	return &MembershipRepository{db: db}
}

func (r *MembershipRepository) GetByUserID(ctx context.Context, userID string) (*models.Membership, error) {
	query := `SELECT id, user_id, tier, is_featured, expires_at, featured_expires_at, created_at, updated_at FROM memberships WHERE user_id = $1`
	var m models.Membership
	err := r.db.QueryRow(ctx, query, userID).Scan(&m.ID, &m.UserID, &m.Tier, &m.IsFeatured, &m.ExpiresAt, &m.FeaturedExpiresAt, &m.CreatedAt, &m.UpdatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &m, nil
}

// Upsert — used both when a user upgrades to premium (after Razorpay payment) and when
// admin toggles "featured" status.
func (r *MembershipRepository) Upsert(ctx context.Context, m *models.Membership) error {
	query := `INSERT INTO memberships (user_id, tier, is_featured, expires_at, featured_expires_at)
		VALUES ($1,$2,$3,$4,$5)
		ON CONFLICT (user_id) DO UPDATE SET tier = EXCLUDED.tier, is_featured = EXCLUDED.is_featured,
			expires_at = EXCLUDED.expires_at, featured_expires_at = EXCLUDED.featured_expires_at
		RETURNING id, created_at, updated_at`
	return r.db.QueryRow(ctx, query, m.UserID, m.Tier, m.IsFeatured, m.ExpiresAt, m.FeaturedExpiresAt).Scan(&m.ID, &m.CreatedAt, &m.UpdatedAt)
}

// CreatePurchase / ConsumePurchase — BUG FIX (H-07): membership purchase confirmation had no
// idempotency and no payment record at all. A reference is persisted at order-creation time and
// can only be consumed (marked used) exactly once — a retried/duplicate verify call, or a call
// with no real matching purchase, is now rejected instead of unconditionally granting tier days.
func (r *MembershipRepository) CreatePurchase(ctx context.Context, userID, reference, kind string, amount float64) error {
	_, err := r.db.Exec(ctx, `INSERT INTO membership_purchases (user_id, reference, kind, amount) VALUES ($1,$2,$3,$4)`,
		userID, reference, kind, amount)
	return err
}

// ConsumePurchase marks the reference used and returns the user id and kind it belongs to, or
// ("", "", nil) if the reference doesn't exist or was already consumed.
//
// BUG FIX (C-2): previously returned only user_id — the `kind` column (premium-membership,
// featured-listing, tier-silver, tier-gold, tier-enterprise) was written by CreatePurchase but
// never read back, so consumeReference only checked ownership, not what was actually paid for.
// Any valid reference could be redeemed against any product (e.g. pay for tier-silver, then
// call VerifyTierPayment with tier=enterprise). Now returns kind too so the caller can verify it.
func (r *MembershipRepository) ConsumePurchase(ctx context.Context, reference string) (string, string, error) {
	var userID, kind string
	err := r.db.QueryRow(ctx, `UPDATE membership_purchases SET consumed_at = now()
		WHERE reference = $1 AND consumed_at IS NULL RETURNING user_id, kind`, reference).Scan(&userID, &kind)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", "", nil
		}
		return "", "", err
	}
	return userID, kind, nil
}

// ListFeatured — role filter joins users so exporter/logistics dashboards can show
// "Featured Exporters"/"Featured Logistics" separately.
func (r *MembershipRepository) ListFeatured(ctx context.Context, role string) ([]models.User, error) {
	query := `SELECT u.id, u.role, u.full_name, u.company_name, u.email, u.phone, u.password_hash,
		u.is_active, u.is_email_verified, u.is_phone_verified, u.razorpay_contact_id,
		u.razorpay_fund_account_id, u.created_at, u.updated_at
		FROM users u
		JOIN memberships m ON m.user_id = u.id
		WHERE m.is_featured = true AND (m.expires_at IS NULL OR m.expires_at > now()) AND u.role = $1
		ORDER BY u.full_name`
	rows, err := r.db.Query(ctx, query, role)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.User
	for rows.Next() {
		var u models.User
		if err := rows.Scan(&u.ID, &u.Role, &u.FullName, &u.CompanyName, &u.Email, &u.Phone, &u.PasswordHash,
			&u.IsActive, &u.IsEmailVerified, &u.IsPhoneVerified, &u.RazorpayContactID, &u.RazorpayFundAccountID,
			&u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}
