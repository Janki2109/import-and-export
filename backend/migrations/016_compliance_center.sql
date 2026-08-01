-- ============================================================
-- COMPLIANCE CENTER — additive module, two new tables only.
-- No existing table is modified. No existing code path depends on these tables, so this
-- migration is safe to apply without affecting any current functionality.
-- ============================================================

CREATE TYPE compliance_status AS ENUM ('pending', 'uploaded', 'verified', 'rejected');

-- ---------- COMPLIANCE_RULES (the rule engine's data — never hardcoded in app code) ----------
-- Any of origin_country / destination_country / hs_code / shipping_mode may be NULL, meaning
-- "applies regardless of this dimension" (a wildcard) — e.g. a rule with hs_code = NULL
-- applies to every product on that trade lane. This is what lets new trade routes (e.g.
-- Japan -> Brazil) be supported purely by inserting rows, with zero code changes.
CREATE TABLE compliance_rules (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    origin_country      VARCHAR(100),
    destination_country VARCHAR(100),
    hs_code             VARCHAR(20),
    shipping_mode       VARCHAR(20),  -- air | sea | road | rail, NULL = any mode
    document_name       VARCHAR(150) NOT NULL,
    responsible_role    user_role NOT NULL,  -- importer | exporter | logistics
    mandatory           BOOLEAN NOT NULL DEFAULT true,
    display_order       INT NOT NULL DEFAULT 0,
    description         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_compliance_rules_lookup ON compliance_rules(origin_country, destination_country, hs_code, shipping_mode);

-- ---------- ORDER_COMPLIANCE (checklist generated per order from matching rules) ----------
CREATE TABLE order_compliance (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id            UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    rule_id             UUID REFERENCES compliance_rules(id) ON DELETE SET NULL,
    document_name       VARCHAR(150) NOT NULL,
    responsible_role    user_role NOT NULL,
    mandatory           BOOLEAN NOT NULL DEFAULT true,
    display_order       INT NOT NULL DEFAULT 0,
    description         TEXT,
    status              compliance_status NOT NULL DEFAULT 'pending',
    uploaded_file        TEXT,
    remarks              TEXT,
    verified_by_admin    UUID REFERENCES users(id),
    uploaded_at           TIMESTAMPTZ,
    verified_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(order_id, document_name)
);

CREATE INDEX idx_order_compliance_order ON order_compliance(order_id);
CREATE INDEX idx_order_compliance_status ON order_compliance(status);

-- ---------- COMPLIANCE_DOCUMENT_HISTORY (every upload, for "Version History") ----------
CREATE TABLE compliance_document_history (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_compliance_id UUID NOT NULL REFERENCES order_compliance(id) ON DELETE CASCADE,
    file_url            TEXT NOT NULL,
    uploaded_by         UUID NOT NULL REFERENCES users(id),
    remarks              TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_compliance_doc_history_item ON compliance_document_history(order_compliance_id, created_at);
