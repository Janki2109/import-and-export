-- Adds an "on_hold" escrow state so admin can pause a payment (block auto-release) without
-- releasing or refunding it yet. Purely additive — existing values (created/authorized/
-- held/released/refunded/failed) and every existing row/code path are untouched.
ALTER TYPE payment_status ADD VALUE IF NOT EXISTS 'on_hold';
