-- BUG FIX (H-20): quotations had no currency column at all — when an accepted quotation was
-- converted into an order, CreateOrderInput never carried a currency and CreateOrder always
-- fell back to "INR", so parties who negotiated e.g. 5000 USD ended up with an order created as
-- ₹5,000 INR (~98% under-collection against the agreed contract). RFQs get the same column so
-- the currency the importer requested in can be carried forward to any quotation submitted
-- against it.
ALTER TABLE rfqs ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'INR';
ALTER TABLE quotations ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'INR';
