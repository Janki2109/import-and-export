-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — PUSH NOTIFICATION DEVICE TOKENS
-- ============================================================

CREATE TABLE device_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token       TEXT NOT NULL UNIQUE,
    platform    VARCHAR(20) NOT NULL DEFAULT 'android', -- android | ios
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
