CREATE TABLE IF NOT EXISTS device_pairings (
 pairing_id uuid PRIMARY KEY,
 account_id uuid NOT NULL REFERENCES accounts ON DELETE CASCADE,
 creator_session_hash bytea NOT NULL REFERENCES sessions(token_hash) ON DELETE CASCADE,
 auth_verifier bytea NOT NULL,
 key_hash bytea NOT NULL CHECK(octet_length(key_hash)=32),
 encrypted_dek bytea NOT NULL CHECK(octet_length(encrypted_dek)=60),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '5 minutes',
 target_device_id uuid,
 target_priority smallint CHECK(target_priority BETWEEN 1 AND 4),
 poll_hash bytea,
 approved boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS device_pairings_expiry ON device_pairings(expires_at);
