-- Profile module additions — purely additive (new nullable columns), no existing
-- column/behavior changes. Powers GET/PUT /users/me (avatar) and the importer's
-- "Products Imported" / "Preferred Shipping Mode" business-details fields on their
-- company profile.

ALTER TABLE users ADD COLUMN avatar_url TEXT;

ALTER TABLE companies ADD COLUMN products_imported TEXT;
ALTER TABLE companies ADD COLUMN preferred_shipping_mode VARCHAR(20);
