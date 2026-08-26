package store_test

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/nobledeveloper01/grid/server/internal/allocation"
	"github.com/nobledeveloper01/grid/server/internal/statement"
	"github.com/nobledeveloper01/grid/server/internal/store"
)

// One suite, both implementations.
//
// The in-memory store is what every other test in this repository runs
// against. If it drifts from Postgres, those tests are asserting the
// behaviour of a fake — which is worse than not having them, because they are
// green while the deployed thing is wrong.
//
// The Postgres half runs when GRID_TEST_DATABASE_URL is set and skips
// otherwise, so `go test ./...` works on a laptop with no database and CI can
// still exercise the real one.

var fixed = time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC)

func fixture(id, token, shareID string) statement.Statement {
	alloc := allocation.Split(allocation.ByRooms, 6_509_800, 310_400,
		[]allocation.Occupant{
			{ID: "a", Name: "Main house", Rooms: 3},
			{ID: "b", Name: "Boys quarters", Rooms: 1},
		})

	return statement.Statement{
		ID:          id,
		Token:       token,
		PropertyID:  "compound-1",
		MeterNumber: "04123456789",
		DisCo:       "Ikeja Electric",
		PeriodStart: fixed.AddDate(0, 0, -30),
		PeriodEnd:   fixed,
		Allocation:  alloc,
		ShareID:     shareID,
		IssuedAt:    fixed,
		ExpiresAt:   fixed.Add(statement.DefaultLifetime),
	}
}

type factory struct {
	name string
	open func(t *testing.T) store.Store
}

func factories(t *testing.T) []factory {
	t.Helper()
	out := []factory{
		{
			name: "memory",
			open: func(t *testing.T) store.Store { return store.NewMemory() },
		},
	}

	url := os.Getenv("GRID_TEST_DATABASE_URL")
	if url == "" {
		t.Log("GRID_TEST_DATABASE_URL not set — skipping the Postgres half. " +
			"The fake is the only thing under test.")
		return out
	}

	out = append(out, factory{
		name: "postgres",
		open: func(t *testing.T) store.Store {
			t.Helper()
			db, err := sql.Open("pgx", url)
			if err != nil {
				t.Fatalf("opening the database: %v", err)
			}
			pg := store.NewPostgres(db)
			ctx := t.Context()
			if err := pg.Migrate(ctx); err != nil {
				t.Fatalf("migrating: %v", err)
			}
			// Each test gets a clean table. Sharing one across tests turns an
			// ordering change into a mystery failure.
			if _, err := db.ExecContext(ctx, `TRUNCATE statements`); err != nil {
				t.Fatalf("clearing statements: %v", err)
			}
			t.Cleanup(func() { _ = pg.Close() })
			return pg
		},
	})
	return out
}

func run(t *testing.T, name string, body func(*testing.T, store.Store)) {
	t.Helper()
	for _, f := range factories(t) {
		t.Run(f.name+"/"+name, func(t *testing.T) {
			body(t, f.open(t))
		})
	}
}

func TestConformance(t *testing.T) {
	ctx := context.Background()

	run(t, "a saved statement comes back by token", func(t *testing.T, s store.Store) {
		want := fixture("s1", "token-1", "a")
		if err := s.PutStatement(ctx, "landlord-1", want); err != nil {
			t.Fatal(err)
		}

		got, err := s.ByToken(ctx, "token-1", fixed)
		if err != nil {
			t.Fatal(err)
		}
		if got.ID != want.ID || got.ShareID != want.ShareID {
			t.Fatalf("got %+v", got)
		}
		// The allocation has to survive the round trip intact — it is what the
		// tenant is shown, and a statement that loses its arithmetic on the
		// way to the database is worse than one that was never issued.
		if len(got.Allocation.Shares) != 2 {
			t.Fatalf("allocation lost its shares: %+v", got.Allocation)
		}
		if !got.Allocation.SumsExactly() {
			t.Fatal("the allocation no longer balances after a round trip")
		}
		if got.Allocation.RemainderGivenTo == "" {
			t.Fatal("the remainder attribution was lost")
		}
	})

	run(t, "an unknown token is not found", func(t *testing.T, s store.Store) {
		if _, err := s.ByToken(ctx, "nope", fixed); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("got %v, want ErrNotFound", err)
		}
	})

	run(t, "an aged-out link is expired, not missing", func(t *testing.T, s store.Store) {
		// Distinct on purpose: "ask for a new link" is actionable, and "this
		// does not exist" sends somebody to argue about the wrong thing.
		if err := s.PutStatement(ctx, "landlord-1", fixture("s1", "token-1", "a")); err != nil {
			t.Fatal(err)
		}
		later := fixed.Add(statement.DefaultLifetime + time.Hour)
		if _, err := s.ByToken(ctx, "token-1", later); !errors.Is(err, store.ErrExpired) {
			t.Fatalf("got %v, want ErrExpired", err)
		}
	})

	run(t, "a landlord sees only their own", func(t *testing.T, s store.Store) {
		if err := s.PutStatement(ctx, "landlord-1", fixture("s1", "t1", "a")); err != nil {
			t.Fatal(err)
		}
		if err := s.PutStatement(ctx, "landlord-2", fixture("s2", "t2", "a")); err != nil {
			t.Fatal(err)
		}

		mine, err := s.StatementsFor(ctx, "landlord-1")
		if err != nil {
			t.Fatal(err)
		}
		if len(mine) != 1 || mine[0].ID != "s1" {
			t.Fatalf("got %d statements: %+v", len(mine), mine)
		}
	})

	run(t, "revoking kills the link", func(t *testing.T, s store.Store) {
		if err := s.PutStatement(ctx, "landlord-1", fixture("s1", "t1", "a")); err != nil {
			t.Fatal(err)
		}
		if err := s.Revoke(ctx, "landlord-1", "s1"); err != nil {
			t.Fatal(err)
		}
		if _, err := s.ByToken(ctx, "t1", fixed); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("a revoked link still opened: %v", err)
		}
	})

	run(t, "another landlord cannot revoke, and is told not-found",
		func(t *testing.T, s store.Store) {
			// Not forbidden: a 403 would confirm the statement exists.
			if err := s.PutStatement(ctx, "landlord-1", fixture("s1", "t1", "a")); err != nil {
				t.Fatal(err)
			}
			if err := s.Revoke(ctx, "landlord-2", "s1"); !errors.Is(err, store.ErrNotFound) {
				t.Fatalf("got %v, want ErrNotFound", err)
			}
			// And it is still there.
			if _, err := s.ByToken(ctx, "t1", fixed); err != nil {
				t.Fatalf("the statement was removed by the wrong landlord: %v", err)
			}
		})

	run(t, "revoking something that never existed is not found",
		func(t *testing.T, s store.Store) {
			if err := s.Revoke(ctx, "landlord-1", "ghost"); !errors.Is(err, store.ErrNotFound) {
				t.Fatalf("got %v, want ErrNotFound", err)
			}
		})

	run(t, "re-saving the same id updates rather than duplicating",
		func(t *testing.T, s store.Store) {
			first := fixture("s1", "t1", "a")
			if err := s.PutStatement(ctx, "landlord-1", first); err != nil {
				t.Fatal(err)
			}
			second := first
			second.ExpiresAt = fixed.Add(2 * statement.DefaultLifetime)
			if err := s.PutStatement(ctx, "landlord-1", second); err != nil {
				t.Fatal(err)
			}

			list, err := s.StatementsFor(ctx, "landlord-1")
			if err != nil {
				t.Fatal(err)
			}
			if len(list) != 1 {
				t.Fatalf("got %d statements, want 1", len(list))
			}
		})

	run(t, "a landlord with nothing gets an empty list, not an error",
		func(t *testing.T, s store.Store) {
			list, err := s.StatementsFor(ctx, "nobody")
			if err != nil {
				t.Fatal(err)
			}
			if len(list) != 0 {
				t.Fatalf("got %d", len(list))
			}
		})
}
