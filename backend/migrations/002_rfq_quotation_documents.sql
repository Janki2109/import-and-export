-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — RFQ, QUOTATION & TRADE DOCUMENTS
-- ============================================================

CREATE TYPE rfq_status AS ENUM ('open', 'quoted', 'closed', 'cancelled');
CREATE TYPE quotation_status AS ENUM ('pending', 'accepted', 'rejected', 'expired');
CREATE TYPE document_type AS ENUM ('commercial_invoice', 'packing_list', 'certificate_of_origin');

-- ---------- RFQ (Importer requests a quote) ----------
CREATE TABLE rfqs (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rfq_number          VARCHAR(30) UNIQUE NOT NULL,
    importer_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_name        VARCHAR(255) NOT NULL,
    hsn_code            VARCHAR(20),
    quantity            NUMERIC(14,2) NOT NULL,
    unit                VARCHAR(20) NOT NULL,
    target_price        NUMERIC(14,2),
    destination_country VARCHAR(100) NOT NULL,
    description         TEXT,
    status              rfq_status NOT NULL DEFAULT 'open',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_rfqs_importer ON rfqs(importer_id);
CREATE INDEX idx_rfqs_status ON rfqs(status);

-- ---------- QUOTATION (Exporter responds to an RFQ) ----------
CREATE TABLE quotations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rfq_id          UUID NOT NULL REFERENCES rfqs(id) ON DELETE CASCADE,
    exporter_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    unit_price      NUMERIC(14,2) NOT NULL,
    quantity        NUMERIC(14,2) NOT NULL,
    total_amount    NUMERIC(14,2) NOT NULL,
    validity_date   DATE NOT NULL,
    terms           TEXT,
    status          quotation_status NOT NULL DEFAULT 'pending',
    order_id        UUID REFERENCES orders(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(rfq_id, exporter_id)
);

CREATE INDEX idx_quotations_rfq ON quotations(rfq_id);
CREATE INDEX idx_quotations_exporter ON quotations(exporter_id);

-- ---------- TRADE DOCUMENTS (generated PDFs for an order) ----------
CREATE TABLE documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    type            document_type NOT NULL,
    file_url        TEXT NOT NULL,
    generated_by    UUID NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(order_id, type)
);

CREATE INDEX idx_documents_order ON documents(order_id);

CREATE TRIGGER trg_rfqs_updated_at BEFORE UPDATE ON rfqs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_quotations_updated_at BEFORE UPDATE ON quotations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
