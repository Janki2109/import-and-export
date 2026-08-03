-- Journey 5 (Order/Escrow): "withdrawal should stay pending until approved." Previously a
-- withdrawal immediately inserted a ledger_entries debit row (balance dropped right away) with
-- "pending" only a naming convention in the reference_id string — no actual approval gate.
-- withdrawal_requests separates the request (no ledger effect) from the actual debit (only
-- created when an admin approves it via MarkWithdrawalPaid). Purely additive — ledger_entries
-- itself is untouched, so every existing balance/history read keeps working unchanged.
CREATE TYPE withdrawal_status AS ENUM ('pending', 'paid', 'rejected');

CREATE TABLE IF NOT EXISTS withdrawal_requests (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount           NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status           withdrawal_status NOT NULL DEFAULT 'pending',
    ledger_entry_id  UUID REFERENCES ledger_entries(id),
    processed_by     UUID REFERENCES users(id),
    processed_at     TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_user ON withdrawal_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_status ON withdrawal_requests(status);
