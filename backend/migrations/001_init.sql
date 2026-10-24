CREATE EXTENSION IF NOT EXISTS citext;
CREATE TABLE IF NOT EXISTS accounts (
 account_id uuid PRIMARY KEY, handle citext UNIQUE NOT NULL,
 kdf_salt bytea NOT NULL, kdf_params jsonb NOT NULL, auth_verifier bytea NOT NULL,
 recovery_verifier bytea,
 failed_logins int NOT NULL DEFAULT 0, locked_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS key_wraps (
 id uuid PRIMARY KEY, account_id uuid NOT NULL REFERENCES accounts ON DELETE CASCADE,
 key_version int NOT NULL CHECK(key_version>0),wrap_type text NOT NULL CHECK(wrap_type IN ('passphrase','recovery')),
 wrapped_dek bytea NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(account_id,key_version,wrap_type)
);
CREATE TABLE IF NOT EXISTS devices (
 device_id uuid PRIMARY KEY,account_id uuid NOT NULL REFERENCES accounts ON DELETE CASCADE,
 priority smallint NOT NULL CHECK(priority BETWEEN 1 AND 4),created_at timestamptz NOT NULL DEFAULT now(),last_seen_at timestamptz,revoked_at timestamptz
);
CREATE TABLE IF NOT EXISTS sessions (
 token_hash bytea PRIMARY KEY,account_id uuid NOT NULL REFERENCES accounts ON DELETE CASCADE,
 device_id uuid NOT NULL REFERENCES devices ON DELETE CASCADE,expires_at timestamptz NOT NULL
);
CREATE SEQUENCE IF NOT EXISTS blob_seq;
CREATE TABLE IF NOT EXISTS blobs (
 account_id uuid NOT NULL REFERENCES accounts ON DELETE CASCADE,row_id uuid NOT NULL,
 version int NOT NULL CHECK(version>0),seq bigint NOT NULL DEFAULT nextval('blob_seq'),key_version int NOT NULL CHECK(key_version>0),
 envelope bytea,deleted boolean NOT NULL DEFAULT false,updated_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(account_id,row_id),CHECK(deleted OR envelope IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS blobs_pull ON blobs(account_id,seq);
CREATE TABLE IF NOT EXISTS leases (
 account_id uuid NOT NULL REFERENCES accounts ON DELETE CASCADE,lease_key bytea NOT NULL,
 holder_device_id uuid NOT NULL,priority smallint NOT NULL,state text NOT NULL CHECK(state IN ('held','done')),
 acquired_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL,PRIMARY KEY(account_id,lease_key)
);
CREATE TABLE IF NOT EXISTS request_limits (
 scope text PRIMARY KEY,window_start timestamptz NOT NULL DEFAULT now(),count int NOT NULL DEFAULT 1
);
