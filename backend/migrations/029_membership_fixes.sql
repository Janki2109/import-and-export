-- BUG FIX (H-09): featured-listing placement and subscription tier previously shared ONE
-- expires_at column — buying a (cheaper) featured listing extended the (more expensive)
-- subscription tier's expiry by 30 days, letting a user renew Enterprise indefinitely at the
-- featured-listing price. Featured placement now has its own expiry column.
ALTER TABLE memberships ADD COLUMN IF NOT EXISTS featured_expires_at TIMESTAMPTZ;

-- BUG FIX (H-07): membership/tier "purchase confirmation" had no idempotency and no payment
-- record at all — Verify* took only a user id and unconditionally added 30 days, so a
-- double-tap/retry granted 60 days for one payment, and nothing stopped an authenticated user
-- from calling verify-tier in a loop with no payment ever made. Each purchase reference is now
-- persisted and can only be consumed once.
CREATE TABLE IF NOT EXISTS membership_purchases (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reference   VARCHAR(255) NOT NULL UNIQUE,
    kind        VARCHAR(50) NOT NULL, -- 'premium' | 'featured' | 'tier-silver' | 'tier-gold' | 'tier-enterprise'
    amount      NUMERIC(14,2) NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_membership_purchases_user ON membership_purchases(user_id);
