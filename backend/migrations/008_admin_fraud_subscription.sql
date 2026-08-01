-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — ADMIN, FRAUD SIGNALS, SUBSCRIPTION TIERS, API KEYS
-- ============================================================

-- ---------- LOGIN ATTEMPTS (fraud signal input) ----------
CREATE TABLE login_attempts (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email       VARCHAR(150) NOT NULL,
    success     BOOLEAN NOT NULL,
    ip_address  VARCHAR(64),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_login_attempts_email_time ON login_attempts(email, created_at);

-- ---------- SUBSCRIPTION TIERS (replaces the free/premium-only membership_tier) ----------
ALTER TYPE membership_tier ADD VALUE IF NOT EXISTS 'silver';
ALTER TYPE membership_tier ADD VALUE IF NOT EXISTS 'gold';
ALTER TYPE membership_tier ADD VALUE IF NOT EXISTS 'enterprise';

-- ---------- API KEYS (Enterprise-tier programmatic access) ----------
CREATE TABLE api_keys (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_hash    VARCHAR(255) NOT NULL UNIQUE,
    label       VARCHAR(100),
    last_used_at TIMESTAMPTZ,
    revoked     BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_api_keys_user ON api_keys(user_id);
