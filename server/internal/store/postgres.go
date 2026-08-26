package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/nobledeveloper01/grid/server/internal/statement"
	"github.com/nobledeveloper01/grid/server/migrations"
)

// Postgres is the durable implementation of Store.
//
// It is held to the same conformance suite as Memory, so the fake used in
// tests cannot drift from the real thing. That pattern has already earned its
// keep elsewhere; here the divergence it guards against is subtle — an
// in-memory map will happily hold two statements with the same token, and
// Postgres will not, and the one that matters is the one with the constraint.
//
// The driver is not imported here. `database/sql` takes whatever the caller
// registered, so the server binary chooses `pgx` or `lib/pq` and this file
// stays free of either — which keeps the store testable against any
// `*sql.DB`, including sqlmock.
type Postgres struct {
	db *sql.DB
}

func NewPostgres(db *sql.DB) *Postgres {
	return &Postgres{db: db}
}

// Migrate applies every embedded migration, in order, once each.
//
// A ledger rather than a "run the files" script: without one, applying the
// schema by hand leaves every later run reporting the migration as pending
// and then failing on a table that already exists, which is a confusing way
// to spend an afternoon.
func (p *Postgres) Migrate(ctx context.Context) error {
	if _, err := p.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			name       TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)`); err != nil {
		return fmt.Errorf("creating the migration ledger: %w", err)
	}

	entries, err := migrations.FS.ReadDir(".")
	if err != nil {
		return fmt.Errorf("reading migrations: %w", err)
	}

	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() {
			names = append(names, e.Name())
		}
	}
	// Lexical order is the intended order; the numeric prefix makes the two
	// the same thing.
	sort.Strings(names)

	for _, name := range names {
		var applied bool
		err := p.db.QueryRowContext(ctx,
			`SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE name = $1)`,
			name,
		).Scan(&applied)
		if err != nil {
			return fmt.Errorf("checking migration %s: %w", name, err)
		}
		if applied {
			continue
		}

		body, err := migrations.FS.ReadFile(name)
		if err != nil {
			return fmt.Errorf("reading %s: %w", name, err)
		}

		// The migration and its ledger entry go in together. A migration that
		// applied but was not recorded is the same failure as one that was
		// recorded but did not apply, and a transaction rules out both.
		tx, err := p.db.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("starting %s: %w", name, err)
		}
		if _, err := tx.ExecContext(ctx, string(body)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("applying %s: %w", name, err)
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO schema_migrations (name) VALUES ($1)`, name,
		); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("recording %s: %w", name, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("committing %s: %w", name, err)
		}
	}
	return nil
}

func (p *Postgres) PutStatement(
	ctx context.Context,
	landlordID string,
	s statement.Statement,
) error {
	allocation, err := json.Marshal(s.Allocation)
	if err != nil {
		return fmt.Errorf("encoding the allocation: %w", err)
	}

	_, err = p.db.ExecContext(ctx, `
		INSERT INTO statements (
			id, landlord_id, token, property_id, meter_number, disco,
			period_start, period_end, allocation, share_id,
			issued_at, expires_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
		ON CONFLICT (id) DO UPDATE SET
			allocation = EXCLUDED.allocation,
			expires_at = EXCLUDED.expires_at`,
		s.ID, landlordID, s.Token, s.PropertyID, s.MeterNumber, s.DisCo,
		s.PeriodStart, s.PeriodEnd, allocation, s.ShareID,
		s.IssuedAt, s.ExpiresAt,
	)
	if err != nil {
		return fmt.Errorf("saving the statement: %w", err)
	}
	return nil
}

func (p *Postgres) StatementsFor(
	ctx context.Context,
	landlordID string,
) ([]statement.Statement, error) {
	rows, err := p.db.QueryContext(ctx, `
		SELECT id, token, property_id, meter_number, disco,
		       period_start, period_end, allocation, share_id,
		       issued_at, expires_at
		FROM statements
		WHERE landlord_id = $1
		ORDER BY issued_at DESC`,
		landlordID,
	)
	if err != nil {
		return nil, fmt.Errorf("listing statements: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var out []statement.Statement
	for rows.Next() {
		s, err := scanStatement(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// ByToken is deliberately not landlord-scoped: it is what a tenant with no
// account uses, and the token is the entire authorisation.
func (p *Postgres) ByToken(
	ctx context.Context,
	token string,
	now time.Time,
) (statement.Statement, error) {
	row := p.db.QueryRowContext(ctx, `
		SELECT id, token, property_id, meter_number, disco,
		       period_start, period_end, allocation, share_id,
		       issued_at, expires_at
		FROM statements
		WHERE token = $1`,
		token,
	)

	s, err := scanStatement(row)
	if errors.Is(err, sql.ErrNoRows) {
		return statement.Statement{}, ErrNotFound
	}
	if err != nil {
		return statement.Statement{}, err
	}

	// Expiry is checked here rather than in the WHERE clause, so an aged-out
	// link can be told apart from one that never existed. "Ask for a new
	// link" is actionable; "this does not exist" sends somebody to argue
	// about the wrong thing.
	if s.Expired(now) {
		return statement.Statement{}, ErrExpired
	}
	return s, nil
}

func (p *Postgres) Revoke(ctx context.Context, landlordID, id string) error {
	// The landlord scope rides in the same statement as the delete. Checking
	// ownership first and deleting second leaves a window, and more
	// importantly leaves two places for the scope to be forgotten.
	result, err := p.db.ExecContext(ctx,
		`DELETE FROM statements WHERE id = $1 AND landlord_id = $2`,
		id, landlordID,
	)
	if err != nil {
		return fmt.Errorf("revoking: %w", err)
	}

	affected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("revoking: %w", err)
	}
	if affected == 0 {
		// Not-found rather than forbidden, whether the row is missing or
		// belongs to somebody else: a 403 would confirm it exists.
		return ErrNotFound
	}
	return nil
}

func (p *Postgres) Close() error { return p.db.Close() }

// scanner is what both *sql.Row and *sql.Rows satisfy.
type scanner interface {
	Scan(dest ...any) error
}

func scanStatement(s scanner) (statement.Statement, error) {
	var out statement.Statement
	var allocation []byte

	if err := s.Scan(
		&out.ID, &out.Token, &out.PropertyID, &out.MeterNumber, &out.DisCo,
		&out.PeriodStart, &out.PeriodEnd, &allocation, &out.ShareID,
		&out.IssuedAt, &out.ExpiresAt,
	); err != nil {
		return statement.Statement{}, err
	}

	if err := json.Unmarshal(allocation, &out.Allocation); err != nil {
		return statement.Statement{}, fmt.Errorf(
			"statement %s holds an allocation this version cannot read: %w",
			out.ID, err,
		)
	}
	return out, nil
}
