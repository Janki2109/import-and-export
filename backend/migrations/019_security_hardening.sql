-- Enterprise security hardening — strictly additive. No existing column/table is altered
-- in a breaking way (only new nullable/defaulted columns and brand-new tables), so every
-- existing query/service keeps working unchanged.

-- Login history enrichment (was: email, success, ip_address, created_at only).
ALTER TABLE login_attempts ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id);
ALTER TABLE login_attempts ADD COLUMN IF NOT EXISTS device_id VARCHAR(255);
ALTER TABLE login_attempts ADD COLUMN IF NOT EXISTS user_agent TEXT;
ALTER TABLE login_attempts ADD COLUMN IF NOT EXISTS country VARCHAR(100);
CREATE INDEX IF NOT EXISTS idx_login_attempts_user ON login_attempts(user_id);

-- Account flagging (fraud detection outcomes surface here for admin review).
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_flagged BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS flagged_reason TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS flagged_at TIMESTAMPTZ;

-- Device registration / trusted devices / "logout this device" / session management.
CREATE TABLE IF NOT EXISTS user_devices (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id     VARCHAR(255) NOT NULL, -- client-generated stable fingerprint (installation id)
    device_name   VARCHAR(150),
    platform      VARCHAR(20),
    trusted       BOOLEAN NOT NULL DEFAULT false,
    is_active     BOOLEAN NOT NULL DEFAULT true, -- false once explicitly logged out
    first_seen    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_ip       VARCHAR(64),
    last_country  VARCHAR(100),
    UNIQUE(user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_user_devices_user ON user_devices(user_id);

-- Document access/download logs (Part 3 + Part 10 — who viewed/downloaded which file, when).
CREATE TABLE IF NOT EXISTS document_access_logs (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    storage_key  TEXT NOT NULL,
    user_id      UUID REFERENCES users(id),
    action       VARCHAR(20) NOT NULL, -- view | download
    ip_address   VARCHAR(64),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_doc_access_logs_key ON document_access_logs(storage_key);
CREATE INDEX IF NOT EXISTS idx_doc_access_logs_user ON document_access_logs(user_id);

-- Persisted fraud-detection findings (previously computed on-demand only, never stored or
-- notified — this is what lets Part 7's "Notify Admin" and account-flagging actually happen).
CREATE TABLE IF NOT EXISTS security_flags (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      UUID REFERENCES users(id),
    rule         VARCHAR(100) NOT NULL,
    severity     VARCHAR(20) NOT NULL, -- low | medium | high
    description  TEXT NOT NULL,
    resolved     BOOLEAN NOT NULL DEFAULT false,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_security_flags_user ON security_flags(user_id);
CREATE INDEX IF NOT EXISTS idx_security_flags_resolved ON security_flags(resolved);
