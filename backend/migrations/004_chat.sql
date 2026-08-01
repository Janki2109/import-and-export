-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — CHAT
-- Importer<->Exporter and Exporter<->Logistics messaging, with
-- file/document/quotation sharing. Role-pair validity is enforced
-- in the service layer (not the schema) since roles can change/expand.
-- ============================================================

CREATE TYPE message_type AS ENUM ('text', 'file', 'document', 'quotation');

-- One row per (unordered) pair of participants — participant_one_id is always the
-- lexicographically smaller UUID so (A,B) and (B,A) can never create duplicate rows.
CREATE TABLE conversations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    participant_one_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant_two_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(participant_one_id, participant_two_id)
);

CREATE INDEX idx_conversations_participant_one ON conversations(participant_one_id);
CREATE INDEX idx_conversations_participant_two ON conversations(participant_two_id);

CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL REFERENCES users(id),
    type            message_type NOT NULL DEFAULT 'text',
    content         TEXT,
    file_url        TEXT,
    quotation_id    UUID REFERENCES quotations(id),
    is_read         BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at);
CREATE INDEX idx_messages_sender ON messages(sender_id);
