-- Admin Chat Management needs an Archive action — purely additive, defaults false so every
-- existing conversation behaves exactly as before.
ALTER TABLE conversations ADD COLUMN is_archived BOOLEAN NOT NULL DEFAULT false;
