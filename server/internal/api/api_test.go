package api

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/nobledeveloper01/grid/server/internal/allocation"
	"github.com/nobledeveloper01/grid/server/internal/statement"
	"github.com/nobledeveloper01/grid/server/internal/store"
)

var fixedNow = time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC)

func newServer(t *testing.T) (http.Handler, *store.Memory) {
	t.Helper()
	st := store.NewMemory()
	s := New(Options{
		Store:  st,
		Now:    func() time.Time { return fixedNow },
		Logger: slog.New(slog.DiscardHandler),
		Keys:   map[string]string{"secret-key": "landlord-1"},
	})
	return s.Routes(), st
}

func createBody() createStatementRequest {
	return createStatementRequest{
		PropertyID:       "compound-1",
		MeterNumber:      "04123456789",
		DisCo:            "Ikeja Electric",
		PeriodStart:      fixedNow.AddDate(0, 0, -30),
		PeriodEnd:        fixedNow,
		Rule:             allocation.ByRooms,
		TotalKobo:        6_509_800,
		TotalEnergyMilli: 310_400,
		Occupants: []allocation.Occupant{
			{ID: "a", Name: "Main house", Rooms: 3},
			{ID: "b", Name: "Boys quarters", Rooms: 1},
			{ID: "c", Name: "Shop in front", Rooms: 1},
		},
	}
}

func post(t *testing.T, h http.Handler, key string, body any) *httptest.ResponseRecorder {
	t.Helper()
	raw, _ := json.Marshal(body)
	r := httptest.NewRequest(http.MethodPost, "/v1/statements", bytes.NewReader(raw))
	if key != "" {
		r.Header.Set("Authorization", "Bearer "+key)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestUnauthenticatedCannotIssue(t *testing.T) {
	h, _ := newServer(t)
	if got := post(t, h, "", createBody()).Code; got != http.StatusUnauthorized {
		t.Fatalf("got %d, want 401", got)
	}
	if got := post(t, h, "wrong", createBody()).Code; got != http.StatusUnauthorized {
		t.Fatalf("got %d, want 401", got)
	}
}

func TestIssuesOneLinkPerHousehold(t *testing.T) {
	h, _ := newServer(t)
	w := post(t, h, "secret-key", createBody())
	if w.Code != http.StatusCreated {
		t.Fatalf("got %d: %s", w.Code, w.Body.String())
	}

	var resp createStatementResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Statements) != 3 {
		t.Fatalf("got %d statements, want 3", len(resp.Statements))
	}

	// The shares must sum to the meter total. This is the phase 6 invariant
	// and it is asserted on what the API actually returned, not on what the
	// engine computed internally.
	var sum int64
	for _, s := range resp.Statements {
		sum += s.AmountKobo
	}
	if sum != createBody().TotalKobo {
		t.Fatalf("issued shares sum to %d, meter total is %d",
			sum, createBody().TotalKobo)
	}
}

func TestShareLinksAreUnguessableAndDistinct(t *testing.T) {
	h, _ := newServer(t)
	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", createBody()).Body.Bytes(), &resp)

	seen := map[string]bool{}
	for _, s := range resp.Statements {
		token := strings.TrimPrefix(s.ShareURL, "/s/")
		if len(token) < 40 {
			t.Fatalf("token %q is too short to be unguessable", token)
		}
		if seen[token] {
			t.Fatal("two households were issued the same link")
		}
		seen[token] = true
	}
}

// TestTenantOpensWithoutAnAccount is phase 6's exit gate, as a test.
func TestTenantOpensWithoutAnAccount(t *testing.T) {
	h, _ := newServer(t)
	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", createBody()).Body.Bytes(), &resp)

	r := httptest.NewRequest(http.MethodGet, resp.Statements[0].ShareURL, nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("got %d, want 200 with no credentials at all", w.Code)
	}
	body := w.Body.String()
	if !strings.Contains(body, "Main house") {
		t.Error("the statement does not name the household it is addressed to")
	}
	// The whole split travels with it: a tenant who can see only their own
	// number is being asked to trust the arithmetic rather than check it.
	for _, name := range []string{"Boys quarters", "Shop in front"} {
		if !strings.Contains(body, name) {
			t.Errorf("the page hides %q, so the split cannot be checked", name)
		}
	}
	if !strings.Contains(body, "add up to the meter total exactly") {
		t.Error("the page does not state that the shares balance")
	}
}

func TestStatementPageIsNotCachedOrIndexed(t *testing.T) {
	h, _ := newServer(t)
	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", createBody()).Body.Bytes(), &resp)

	r := httptest.NewRequest(http.MethodGet, resp.Statements[0].ShareURL, nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	// A share link is a capability. Letting a proxy cache it, or a crawler
	// index it, is the same disclosure as forwarding the message.
	if !strings.Contains(w.Header().Get("Cache-Control"), "no-store") {
		t.Error("statement is cacheable")
	}
	if w.Header().Get("X-Robots-Tag") == "" {
		t.Error("statement is indexable")
	}
	if w.Header().Get("Referrer-Policy") != "no-referrer" {
		t.Error("the token would leak in the referrer header")
	}
}

func TestExpiredLinkSaysSoRatherThanNotFound(t *testing.T) {
	st := store.NewMemory()
	s := New(Options{
		Store:  st,
		Now:    func() time.Time { return fixedNow },
		Logger: slog.New(slog.DiscardHandler),
		Keys:   map[string]string{"secret-key": "landlord-1"},
	})
	h := s.Routes()

	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", createBody()).Body.Bytes(), &resp)
	token := strings.TrimPrefix(resp.Statements[0].ShareURL, "/s/")

	// Look it up well past the lifetime.
	later := fixedNow.Add(statement.DefaultLifetime + time.Hour)
	if _, err := st.ByToken(t.Context(), token, later); err != store.ErrExpired {
		t.Fatalf("got %v, want ErrExpired — a tenant needs to be told to ask "+
			"for a new link, not that their statement does not exist", err)
	}
}

func TestRevokedLinkStopsOpening(t *testing.T) {
	h, _ := newServer(t)
	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", createBody()).Body.Bytes(), &resp)

	del := httptest.NewRequest(http.MethodDelete,
		"/v1/statements/"+resp.Statements[0].ID, nil)
	del.Header.Set("Authorization", "Bearer secret-key")
	dw := httptest.NewRecorder()
	h.ServeHTTP(dw, del)
	if dw.Code != http.StatusNoContent {
		t.Fatalf("revoke got %d: %s", dw.Code, dw.Body.String())
	}

	r := httptest.NewRequest(http.MethodGet, resp.Statements[0].ShareURL, nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusNotFound {
		t.Fatalf("a revoked link still opened: %d", w.Code)
	}
}

func TestAnotherLandlordCannotRevoke(t *testing.T) {
	st := store.NewMemory()
	s := New(Options{
		Store:  st,
		Now:    func() time.Time { return fixedNow },
		Logger: slog.New(slog.DiscardHandler),
		Keys: map[string]string{
			"secret-key": "landlord-1",
			"other-key":  "landlord-2",
		},
	})
	h := s.Routes()

	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", createBody()).Body.Bytes(), &resp)

	del := httptest.NewRequest(http.MethodDelete,
		"/v1/statements/"+resp.Statements[0].ID, nil)
	del.Header.Set("Authorization", "Bearer other-key")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, del)

	// Not-found rather than forbidden: a 403 confirms the statement exists.
	if w.Code != http.StatusNotFound {
		t.Fatalf("got %d, want 404", w.Code)
	}
}

func TestOccupantNamesAreEscaped(t *testing.T) {
	// Names are typed by a landlord on a phone, which is exactly the kind of
	// input that eventually contains an angle bracket.
	h, _ := newServer(t)
	body := createBody()
	body.Occupants[0].Name = `<script>alert(1)</script>`

	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", body).Body.Bytes(), &resp)

	r := httptest.NewRequest(http.MethodGet, resp.Statements[0].ShareURL, nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if strings.Contains(w.Body.String(), "<script>alert(1)</script>") {
		t.Fatal("occupant name was interpolated unescaped")
	}
	if !strings.Contains(w.Body.String(), "&lt;script&gt;") {
		t.Fatal("the name is missing entirely; it should be escaped, not dropped")
	}
}

func TestRefusesToSplitNothing(t *testing.T) {
	h, _ := newServer(t)

	empty := createBody()
	empty.Occupants = nil
	if got := post(t, h, "secret-key", empty).Code; got != http.StatusBadRequest {
		t.Errorf("no occupants: got %d, want 400", got)
	}

	zero := createBody()
	zero.TotalKobo = 0
	if got := post(t, h, "secret-key", zero).Code; got != http.StatusBadRequest {
		t.Errorf("zero total: got %d, want 400", got)
	}
}

func TestTokenIsNotLogged(t *testing.T) {
	// A share link in a log file is the same disclosure as one in a forwarded
	// message.
	var buf bytes.Buffer
	st := store.NewMemory()
	s := New(Options{
		Store:  st,
		Now:    func() time.Time { return fixedNow },
		Logger: slog.New(slog.NewTextHandler(&buf, nil)),
		Keys:   map[string]string{"secret-key": "landlord-1"},
	})
	h := s.Routes()

	var resp createStatementResponse
	_ = json.Unmarshal(post(t, h, "secret-key", createBody()).Body.Bytes(), &resp)
	token := strings.TrimPrefix(resp.Statements[0].ShareURL, "/s/")

	r := httptest.NewRequest(http.MethodGet, resp.Statements[0].ShareURL, nil)
	h.ServeHTTP(httptest.NewRecorder(), r)

	if strings.Contains(buf.String(), token) {
		t.Fatal("the share token appears in the logs")
	}
	if !strings.Contains(buf.String(), "/s/{token}") {
		t.Fatal("the request was not logged at all")
	}
}
