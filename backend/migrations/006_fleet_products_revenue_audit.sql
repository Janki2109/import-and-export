-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — FLEET, PRODUCT CATALOG, REVENUE FEATURES, AUDIT LOG
-- ============================================================

CREATE TYPE vehicle_status AS ENUM ('active', 'inactive', 'maintenance');
CREATE TYPE membership_tier AS ENUM ('free', 'premium');

-- ---------- FLEET (Logistics Partner's vehicles) ----------
CREATE TABLE fleet_vehicles (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    logistics_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vehicle_type        VARCHAR(50) NOT NULL,      -- truck, container_ship, cargo_plane, etc.
    registration_number VARCHAR(50) NOT NULL,
    capacity_kg         NUMERIC(12,2),
    capacity_cbm        NUMERIC(12,2),              -- cubic meters
    service_route        VARCHAR(255),               -- e.g. "Mumbai -> Dubai"
    status               vehicle_status NOT NULL DEFAULT 'active',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(logistics_id, registration_number)
);

CREATE INDEX idx_fleet_vehicles_logistics ON fleet_vehicles(logistics_id);

-- ---------- PRODUCT CATALOG (Exporter's listed products) ----------
CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    exporter_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    hsn_code        VARCHAR(20),
    description     TEXT,
    unit            VARCHAR(20) NOT NULL,
    unit_price      NUMERIC(14,2) NOT NULL,
    min_order_qty   NUMERIC(14,2) NOT NULL DEFAULT 1,
    image_url       TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_exporter ON products(exporter_id);
CREATE INDEX idx_products_name ON products USING gin (to_tsvector('english', name));

-- ---------- REVENUE: MEMBERSHIPS ----------
CREATE TABLE memberships (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    tier            membership_tier NOT NULL DEFAULT 'free',
    is_featured     BOOLEAN NOT NULL DEFAULT false,   -- "Featured Exporter" / "Featured Logistics"
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- REVENUE: ADVERTISEMENTS ----------
CREATE TABLE advertisements (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    advertiser_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(255) NOT NULL,
    image_url       TEXT NOT NULL,
    target_url      TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    starts_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    ends_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_advertisements_active ON advertisements(is_active);

-- ---------- AUDIT LOG ----------
CREATE TABLE audit_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id        UUID REFERENCES users(id),
    action          VARCHAR(100) NOT NULL,   -- e.g. "kyc.approve", "dispute.resolve"
    entity_type     VARCHAR(50) NOT NULL,    -- e.g. "kyc_details", "dispute"
    entity_id       VARCHAR(100),
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_actor ON audit_logs(actor_id);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at);

CREATE TRIGGER trg_fleet_vehicles_updated_at BEFORE UPDATE ON fleet_vehicles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_memberships_updated_at BEFORE UPDATE ON memberships FOR EACH ROW EXECUTE FUNCTION set_updated_at();
