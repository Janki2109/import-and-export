-- New RFQ screen: product image is now required at the client, uploaded via the existing
-- presigned-upload flow (category "rfq") and stored with the RFQ so exporters can see it
-- when they view/browse the RFQ. Purely additive, nullable column — existing rows and every
-- existing read/write path keep working exactly as before.
ALTER TABLE rfqs ADD COLUMN IF NOT EXISTS product_image_url TEXT;
