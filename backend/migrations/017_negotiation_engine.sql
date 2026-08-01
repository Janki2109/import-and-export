-- ============================================================
-- NEGOTIATION ENGINE — additive module, two new tables only.
-- No existing table (rfqs, quotations, orders, ...) is altered. Existing code paths
-- (RFQ creation, quotation submission/accept, order creation) are untouched — this module
-- only ever reads them, and its one write into `quotations` (locking in the final agreed
-- values once a negotiation is accepted) touches only plain data columns, reusing the
-- existing, unmodified accept-quotation -> create-order flow for the actual order creation.
-- ============================================================

CREATE TYPE negotiation_status AS ENUM ('open', 'accepted', 'rejected', 'expired', 'closed');
CREATE TYPE negotiation_offer_status AS ENUM ('pending', 'accepted', 'rejected', 'countered');
CREATE TYPE negotiation_party AS ENUM ('importer', 'exporter');

-- ---------- NEGOTIATIONS (one per quotation under negotiation) ----------
CREATE TABLE negotiations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rfq_id          UUID NOT NULL REFERENCES rfqs(id) ON DELETE CASCADE,
    quotation_id    UUID NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
    importer_id     UUID NOT NULL REFERENCES users(id),
    exporter_id     UUID NOT NULL REFERENCES users(id),
    status          negotiation_status NOT NULL DEFAULT 'open',
    current_round   INT NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(quotation_id)
);

CREATE INDEX idx_negotiations_importer ON negotiations(importer_id);
CREATE INDEX idx_negotiations_exporter ON negotiations(exporter_id);
CREATE INDEX idx_negotiations_status ON negotiations(status);

-- ---------- NEGOTIATION_OFFERS (every offer/counter-offer — the structured timeline) ----------
-- Columns beyond the spec's base list (total_price, moq, dispatch_days, validity_date,
-- special_conditions) are additive extras needed to cover the full negotiable-fields list
-- (quantity/MOQ, delivery/dispatch time, validity/quote expiry, special conditions) without
-- cramming them into `remarks` as free text.
CREATE TABLE negotiation_offers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    negotiation_id      UUID NOT NULL REFERENCES negotiations(id) ON DELETE CASCADE,
    round_number        INT NOT NULL,
    created_by          negotiation_party NOT NULL,
    created_by_user_id  UUID NOT NULL REFERENCES users(id),
    unit_price          NUMERIC(14,2) NOT NULL,
    currency            VARCHAR(10) NOT NULL DEFAULT 'INR',
    quantity            NUMERIC(14,2) NOT NULL,
    moq                 NUMERIC(14,2),
    total_price         NUMERIC(14,2) NOT NULL,
    delivery_days       INT,
    dispatch_days       INT,
    shipping_mode       VARCHAR(20),   -- air | sea | road | rail
    incoterm             VARCHAR(10),   -- EXW | FOB | CIF | CFR | DDP | FCA
    payment_terms        VARCHAR(50),
    packaging             VARCHAR(50),
    validity_date         DATE,
    special_conditions    TEXT,
    remarks               TEXT,
    status                negotiation_offer_status NOT NULL DEFAULT 'pending',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_negotiation_offers_negotiation ON negotiation_offers(negotiation_id, round_number);
