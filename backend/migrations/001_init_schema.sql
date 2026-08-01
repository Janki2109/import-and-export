-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — CORE SCHEMA
-- 3 roles: importer, exporter, logistics(3pl) + platform admin
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------- ENUMS ----------
CREATE TYPE user_role AS ENUM ('importer', 'exporter', 'logistics', 'admin');
CREATE TYPE kyc_status AS ENUM ('pending', 'submitted', 'verified', 'rejected');
CREATE TYPE order_status AS ENUM (
    'created',          -- importer created order, awaiting payment
    'payment_held',      -- payment collected, held in escrow
    'accepted',           -- exporter accepted order
    'shipped',            -- handed to logistics
    'in_transit',
    'delivered',           -- logistics confirms delivery (POD uploaded)
    'confirmed',           -- importer confirms receipt (or auto-confirmed)
    'payment_released',    -- money released to exporter
    'disputed',
    'cancelled',
    'refunded'
);
CREATE TYPE payment_status AS ENUM ('created', 'authorized', 'held', 'released', 'refunded', 'failed');
CREATE TYPE shipment_status AS ENUM ('pending', 'assigned', 'picked_up', 'in_transit', 'delivered', 'exception');
CREATE TYPE ledger_entry_type AS ENUM ('credit', 'debit');

-- ---------- USERS ----------
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    role            user_role NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    company_name    VARCHAR(200),
    email           VARCHAR(150) UNIQUE NOT NULL,
    phone           VARCHAR(20) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    is_email_verified BOOLEAN NOT NULL DEFAULT false,
    is_phone_verified BOOLEAN NOT NULL DEFAULT false,
    razorpay_contact_id  VARCHAR(100),      -- for Route payouts (exporter/logistics payees)
    razorpay_fund_account_id VARCHAR(100),  -- linked bank/UPI for payout
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_email ON users(email);

-- ---------- KYC ----------
CREATE TABLE kyc_details (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          kyc_status NOT NULL DEFAULT 'pending',
    pan_number      VARCHAR(20),
    gst_number      VARCHAR(20),
    iec_code        VARCHAR(20),           -- Import Export Code (importer/exporter)
    business_license VARCHAR(50),          -- for logistics/3PL
    pan_doc_url     TEXT,
    gst_doc_url     TEXT,
    iec_doc_url     TEXT,
    address_doc_url TEXT,
    rejection_reason TEXT,
    verified_by     UUID REFERENCES users(id),
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- ---------- ORDERS (the deal between importer & exporter) ----------
CREATE TABLE orders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number        VARCHAR(30) UNIQUE NOT NULL,   -- e.g. OBEI-2026-000123
    importer_id         UUID NOT NULL REFERENCES users(id),
    exporter_id         UUID NOT NULL REFERENCES users(id),
    product_name        VARCHAR(255) NOT NULL,
    hsn_code             VARCHAR(20),
    quantity             NUMERIC(14,2) NOT NULL,
    unit                 VARCHAR(20) NOT NULL,
    unit_price           NUMERIC(14,2) NOT NULL,
    currency             VARCHAR(10) NOT NULL DEFAULT 'INR',
    total_amount          NUMERIC(14,2) NOT NULL,        -- goods value
    platform_fee_percent   NUMERIC(5,2) NOT NULL DEFAULT 2.00,
    platform_fee_amount    NUMERIC(14,2) NOT NULL DEFAULT 0,
    exporter_payout_amount NUMERIC(14,2) NOT NULL DEFAULT 0, -- total - fee
    status                order_status NOT NULL DEFAULT 'created',
    auto_release_days     INT NOT NULL DEFAULT 7,          -- auto-release payment if importer silent
    delivery_address       TEXT,
    notes                  TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_importer ON orders(importer_id);
CREATE INDEX idx_orders_exporter ON orders(exporter_id);
CREATE INDEX idx_orders_status ON orders(status);

-- ---------- ESCROW PAYMENTS ----------
-- One row per order (1:1). Tracks Razorpay order/payment + hold/release lifecycle.
CREATE TABLE escrow_payments (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id                UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    razorpay_order_id       VARCHAR(100),
    razorpay_payment_id     VARCHAR(100),
    razorpay_payout_id      VARCHAR(100),      -- Route payout ref when released
    amount                  NUMERIC(14,2) NOT NULL,
    platform_fee            NUMERIC(14,2) NOT NULL,
    payout_amount            NUMERIC(14,2) NOT NULL,
    status                    payment_status NOT NULL DEFAULT 'created',
    held_at                   TIMESTAMPTZ,
    release_due_at             TIMESTAMPTZ,      -- computed = held_at + auto_release_days
    released_at                TIMESTAMPTZ,
    refunded_at                 TIMESTAMPTZ,
    failure_reason               TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_escrow_status ON escrow_payments(status);
CREATE INDEX idx_escrow_release_due ON escrow_payments(release_due_at) WHERE status = 'held';

-- ---------- SHIPMENTS (3PL Logistics) ----------
CREATE TABLE shipments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id            UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    logistics_id        UUID REFERENCES users(id),     -- assigned 3PL partner
    tracking_number      VARCHAR(50) UNIQUE,
    status                shipment_status NOT NULL DEFAULT 'pending',
    pickup_address        TEXT,
    delivery_address      TEXT,
    carrier_name           VARCHAR(150),
    estimated_delivery      DATE,
    picked_up_at            TIMESTAMPTZ,
    delivered_at             TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_shipments_logistics ON shipments(logistics_id);
CREATE INDEX idx_shipments_status ON shipments(status);

-- Shipment status history (audit trail / tracking timeline)
CREATE TABLE shipment_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shipment_id     UUID NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    status          shipment_status NOT NULL,
    location        VARCHAR(255),
    remarks         TEXT,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- PROOF OF DELIVERY ----------
CREATE TABLE pod_documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shipment_id     UUID NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    uploaded_by     UUID NOT NULL REFERENCES users(id),
    file_url        TEXT NOT NULL,
    file_type       VARCHAR(20) NOT NULL DEFAULT 'image', -- image/pdf
    signature_url   TEXT,
    remarks         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- DISPUTES ----------
CREATE TABLE disputes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    raised_by       UUID NOT NULL REFERENCES users(id),
    reason          TEXT NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'open', -- open, resolved, rejected
    resolution_notes TEXT,
    resolved_by     UUID REFERENCES users(id),
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- LEDGER (financial audit trail — every rupee movement) ----------
CREATE TABLE ledger_entries (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID REFERENCES orders(id),
    user_id         UUID REFERENCES users(id),        -- whose ledger (null = platform)
    entry_type      ledger_entry_type NOT NULL,
    amount          NUMERIC(14,2) NOT NULL,
    balance_after   NUMERIC(14,2),
    description     VARCHAR(255) NOT NULL,
    reference_id    VARCHAR(100),                      -- razorpay payment/payout id
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ledger_user ON ledger_entries(user_id);
CREATE INDEX idx_ledger_order ON ledger_entries(order_id);

-- ---------- NOTIFICATIONS ----------
CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       VARCHAR(200) NOT NULL,
    body        TEXT NOT NULL,
    type        VARCHAR(50) NOT NULL,   -- order_update, payment, shipment, kyc
    reference_id UUID,
    is_read     BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, is_read);

-- ---------- REFRESH TOKENS (JWT) ----------
CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);

-- ---------- TRIGGER: auto-update updated_at ----------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_kyc_updated_at BEFORE UPDATE ON kyc_details FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_escrow_updated_at BEFORE UPDATE ON escrow_payments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_shipments_updated_at BEFORE UPDATE ON shipments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
