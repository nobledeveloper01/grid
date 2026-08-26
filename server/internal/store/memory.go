package store

import (
	"context"
	"sync"
	"time"

	"github.com/nobledeveloper01/grid/server/internal/statement"
)

// Memory is the in-memory implementation. Used by tests, and by the server
// when no database URL is configured — which makes `docker compose up` produce
// something you can click on without provisioning Postgres first.
type Memory struct {
	mu         sync.RWMutex
	byID       map[string]statement.Statement
	byToken    map[string]string
	byLandlord map[string][]string
}

func NewMemory() *Memory {
	return &Memory{
		byID:       map[string]statement.Statement{},
		byToken:    map[string]string{},
		byLandlord: map[string][]string{},
	}
}

func (m *Memory) PutStatement(_ context.Context, landlordID string, s statement.Statement) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if _, exists := m.byID[s.ID]; !exists {
		m.byLandlord[landlordID] = append(m.byLandlord[landlordID], s.ID)
	}
	m.byID[s.ID] = s
	m.byToken[s.Token] = s.ID
	return nil
}

func (m *Memory) StatementsFor(_ context.Context, landlordID string) ([]statement.Statement, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	ids := m.byLandlord[landlordID]
	out := make([]statement.Statement, 0, len(ids))
	for _, id := range ids {
		if s, ok := m.byID[id]; ok {
			out = append(out, s)
		}
	}
	return out, nil
}

func (m *Memory) ByToken(_ context.Context, token string, now time.Time) (statement.Statement, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	id, ok := m.byToken[token]
	if !ok {
		return statement.Statement{}, ErrNotFound
	}
	s, ok := m.byID[id]
	if !ok {
		return statement.Statement{}, ErrNotFound
	}
	if s.Expired(now) {
		return statement.Statement{}, ErrExpired
	}
	return s, nil
}

func (m *Memory) Revoke(_ context.Context, landlordID, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	s, ok := m.byID[id]
	if !ok {
		return ErrNotFound
	}
	// Scope check by ownership rather than by a separate lookup: a landlord
	// must not be able to revoke somebody else's link, and returning
	// ErrNotFound rather than a permission error avoids confirming the
	// statement exists.
	owned := false
	for _, owned_id := range m.byLandlord[landlordID] {
		if owned_id == id {
			owned = true
			break
		}
	}
	if !owned {
		return ErrNotFound
	}

	delete(m.byToken, s.Token)
	delete(m.byID, id)
	return nil
}

func (m *Memory) Close() error { return nil }
