-- Journey 3 (Exporter Discovery): supplier directory, company profiles, ratings, and RFQ
-- targeting. All additive — no existing table/column is altered or removed, so every existing
-- read/write path (company create/edit, RFQ create/browse) keeps working exactly as before.

-- Certifications shown on a company's public profile (ISO, FSSAI, organic, etc.) — free-form
-- list, entered by the company itself when editing its profile.
ALTER TABLE companies ADD COLUMN IF NOT EXISTS certifications TEXT[] NOT NULL DEFAULT '{}';

-- Post-order ratings an importer leaves for the exporter's company (or vice versa is not
-- modeled — only importer-rates-exporter is in scope for Journey 3's "view ratings" on a
-- supplier profile). One rating per order per rater, enforced by the unique constraint.
CREATE TABLE IF NOT EXISTS company_ratings (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    rated_by    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    score       SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (order_id, rated_by)
);
CREATE INDEX IF NOT EXISTS idx_company_ratings_company ON company_ratings(company_id);

-- RFQ targeting: when an importer requests a quotation directly from a specific exporter's
-- profile (Journey 3) rather than posting to the open marketplace, rows here record who it was
-- sent to. An RFQ with zero rows here keeps today's behavior — a fully open broadcast any
-- exporter can browse and quote. An RFQ with rows here is only visible to those exporters (plus
-- the importer who posted it and admin), matching Journey 4's "multiple exporters receive RFQ."
CREATE TABLE IF NOT EXISTS rfq_targets (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rfq_id      UUID NOT NULL REFERENCES rfqs(id) ON DELETE CASCADE,
    exporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (rfq_id, exporter_id)
);
CREATE INDEX IF NOT EXISTS idx_rfq_targets_rfq ON rfq_targets(rfq_id);
CREATE INDEX IF NOT EXISTS idx_rfq_targets_exporter ON rfq_targets(exporter_id);
