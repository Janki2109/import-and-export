-- Journey 9 (Documents): adds the 4 remaining required document types, version history,
-- checksum + digital-signature columns, and secure (encrypted, signed-URL) storage support.
-- Purely additive — no existing column/table is altered destructively, and file_url stays
-- populated (now with a signed URL instead of a permanent public path) so nothing reading it
-- breaks.
ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'export_declaration';
ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'import_declaration';
ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'inspection_certificate';
ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'insurance_certificate';

ALTER TABLE documents ADD COLUMN IF NOT EXISTS storage_key TEXT;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS checksum TEXT;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS signature TEXT;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Every past version of a generated document, kept even after `documents` is overwritten
-- with the new current version — this is what makes "version history" real instead of
-- each regeneration silently destroying the prior copy.
CREATE TABLE IF NOT EXISTS document_versions (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id  UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version      INT NOT NULL,
    storage_key  TEXT NOT NULL,
    checksum     TEXT NOT NULL,
    signature    TEXT NOT NULL,
    generated_by UUID NOT NULL REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (document_id, version)
);
CREATE INDEX IF NOT EXISTS idx_document_versions_document ON document_versions(document_id, version DESC);
