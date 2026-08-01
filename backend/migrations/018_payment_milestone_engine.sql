-- Payment Terms & Milestone Escrow Engine — additive module.
-- New tables only. Does not alter orders, escrow_payments, ledger_entries, or any
-- existing table. Milestone releases reuse ledger_entries via new INSERTs only
-- (same pattern escrow_repository.go already uses for MarkHeld/MarkReleased).

CREATE TYPE payment_model AS ENUM (
    'advance_100',
    'advance_balance',
    'milestone_escrow',
    'letter_of_credit',
    'open_account',
    'custom'
);

CREATE TYPE payment_milestone_status AS ENUM (
    'pending',
    'paid',
    'waiting_approval',
    'approved',
    'released',
    'rejected',
    'on_hold'
);

CREATE TYPE lc_status AS ENUM ('issued', 'pending', 'verified', 'completed');

CREATE TABLE payment_terms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    payment_model payment_model NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'INR',
    total_amount NUMERIC(14,2) NOT NULL,
    -- Letter of Credit fields (only populated when payment_model = 'letter_of_credit')
    lc_number VARCHAR(100),
    lc_bank_name VARCHAR(150),
    lc_expiry_date DATE,
    lc_status lc_status,
    -- Open Account field (only populated when payment_model = 'open_account')
    open_account_days INT,
    status VARCHAR(20) NOT NULL DEFAULT 'active', -- active | completed
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payment_terms_order ON payment_terms(order_id);

CREATE TABLE payment_milestones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    payment_term_id UUID NOT NULL REFERENCES payment_terms(id) ON DELETE CASCADE,
    release_order INT NOT NULL,
    title VARCHAR(150) NOT NULL,
    percentage NUMERIC(5,2) NOT NULL,
    amount NUMERIC(14,2) NOT NULL,
    status payment_milestone_status NOT NULL DEFAULT 'pending',
    trigger_event VARCHAR(30) NOT NULL DEFAULT 'manual_release',
    proof_required BOOLEAN NOT NULL DEFAULT true,
    proof_url TEXT,
    proof_uploaded_at TIMESTAMPTZ,
    uploaded_by UUID REFERENCES users(id),
    paid_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMPTZ,
    remarks TEXT,
    released_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(payment_term_id, release_order)
);

CREATE INDEX idx_payment_milestones_term ON payment_milestones(payment_term_id);
CREATE INDEX idx_payment_milestones_status ON payment_milestones(status);
