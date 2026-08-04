-- Journey 11 "end-to-end encrypted chat": each user's X25519 public key, published so any
-- other user can derive a shared secret with them (ECDH) for E2E message encryption entirely
-- client-side — the server only ever stores/relays the resulting ciphertext, never a key that
-- could decrypt it. Purely additive.
ALTER TABLE users ADD COLUMN IF NOT EXISTS chat_public_key TEXT;
