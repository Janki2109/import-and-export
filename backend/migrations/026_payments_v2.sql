-- Journey 10 (Payments): partial refunds and multi-currency. Additive only.
ALTER TABLE escrow_payments ADD COLUMN IF NOT EXISTS refunded_amount NUMERIC(14,2) NOT NULL DEFAULT 0;

-- orders.currency already exists (VARCHAR, defaults 'INR' at the app layer) — no schema change
-- needed there; this migration documents that CreateOrder now actually accepts a currency
-- rather than hardcoding it (see order_service.go).
