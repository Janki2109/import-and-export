-- Advertisements: add the real fields the "Advertisements" feature needs (description,
-- category, product/service media type, price/contact, and a view counter) — the original
-- table (006_fleet_products_revenue_audit.sql) only had title/image_url/target_url.
ALTER TABLE advertisements
    ADD COLUMN IF NOT EXISTS description  TEXT,
    ADD COLUMN IF NOT EXISTS category     VARCHAR(100),
    ADD COLUMN IF NOT EXISTS media_type   VARCHAR(10) NOT NULL DEFAULT 'image' CHECK (media_type IN ('image', 'video')),
    ADD COLUMN IF NOT EXISTS price        NUMERIC(14, 2),
    ADD COLUMN IF NOT EXISTS contact_info VARCHAR(255),
    ADD COLUMN IF NOT EXISTS views        INT NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_advertisements_category ON advertisements(category);
