-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — COMPANY PROFILE
-- Separate step in onboarding (Login/Register -> Select Role -> Create Company -> KYC -> Dashboard).
-- One company profile per user.
-- ============================================================

CREATE TABLE companies (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    company_name        VARCHAR(200) NOT NULL,
    business_type       VARCHAR(100),
    registration_number VARCHAR(100),
    address             TEXT,
    city                VARCHAR(100),
    country             VARCHAR(100),
    website             VARCHAR(255),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_companies_updated_at BEFORE UPDATE ON companies FOR EACH ROW EXECUTE FUNCTION set_updated_at();
