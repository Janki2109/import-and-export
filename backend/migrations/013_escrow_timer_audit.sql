-- Escrow admin-notification marker (auto-release timer no longer auto-releases — it
-- notifies admin once when the window elapses, so this tracks whether that's happened
-- yet for a given escrow row). Purely additive.
ALTER TABLE escrow_payments ADD COLUMN admin_notified_at TIMESTAMPTZ;
