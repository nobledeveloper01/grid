// Package store is the persistence port.
//
// Two implementations behind one interface, held to one conformance suite, so
// the in-memory store used in tests cannot drift from the Postgres one used in
// production. That pattern is borrowed deliberately: a fake that has quietly
// diverged from the real thing turns a green test suite into a liability.
package store

import (
	"context"
	"errors"
	"time"

	"github.com/nobledeveloper01/grid/server/internal/statement"
)

var (
	ErrNotFound = errors.New("not found")

	// ErrExpired is distinct from ErrNotFound on purpose. A tenant whose link
	// has aged out needs to be told to ask for a new one; being told the
	// statement does not exist would send them to argue with their landlord
	// about something that is not the problem.
	ErrExpired = errors.New("expired")
)

// Store holds statements. Every landlord-scoped method takes landlordID as its
// **first argument**, so a forgotten scope is a compile error rather than a
// data leak.
type Store interface {
	PutStatement(ctx context.Context, landlordID string, s statement.Statement) error

	// StatementsFor lists what a landlord has issued.
	StatementsFor(ctx context.Context, landlordID string) ([]statement.Statement, error)

	// ByToken resolves a share link. Deliberately **not** landlord-scoped: it
	// is what a tenant with no account uses, and the token is the entire
	// authorisation. Returns ErrExpired once the link has aged out.
	ByToken(ctx context.Context, token string, now time.Time) (statement.Statement, error)

	// Revoke kills a share link early — the tenant moved out, or the link was
	// forwarded somewhere it should not have been.
	Revoke(ctx context.Context, landlordID, id string) error

	Close() error
}
