-- Statements, and the links that open them.
--
-- One table. A statement is immutable once issued — the split it records
-- happened, and re-splitting a past period would change what a tenant was
-- told they owed — so there is no update path here beyond revocation, which
-- deletes the row rather than editing it.

CREATE TABLE IF NOT EXISTS statements (
    id           TEXT PRIMARY KEY,
    landlord_id  TEXT        NOT NULL,

    -- The share token. Unique because it is the entire authorisation: two
    -- statements answering to one token would be a cross-tenant disclosure.
    token        TEXT        NOT NULL UNIQUE,

    property_id  TEXT        NOT NULL DEFAULT '',
    meter_number TEXT        NOT NULL DEFAULT '',
    disco        TEXT        NOT NULL DEFAULT '',

    period_start TIMESTAMPTZ NOT NULL,
    period_end   TIMESTAMPTZ NOT NULL,

    -- The whole allocation, as the server computed it. Stored rather than
    -- recomputed on read: the tariff table moves, and a statement issued in
    -- August must still show August's arithmetic in November.
    allocation   JSONB       NOT NULL,
    share_id     TEXT        NOT NULL,

    issued_at    TIMESTAMPTZ NOT NULL,
    expires_at   TIMESTAMPTZ NOT NULL
);

-- The tenant path. Every share-link open is this lookup, and it is the only
-- query on the hot path.
CREATE INDEX IF NOT EXISTS statements_token_idx ON statements (token);

-- The landlord path: what have I issued, newest first.
CREATE INDEX IF NOT EXISTS statements_landlord_idx
    ON statements (landlord_id, issued_at DESC);

-- Expired links are dead weight and a standing disclosure risk. A sweep can
-- use this; nothing depends on it having run.
CREATE INDEX IF NOT EXISTS statements_expiry_idx ON statements (expires_at);
