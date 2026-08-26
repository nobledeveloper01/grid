// Package api is the HTTP surface.
//
// Two audiences with opposite needs. A landlord authenticates and issues
// statements; a tenant holds a link and reads one. The tenant path has no
// account, no login and no app — phase 6's exit gate is that they can open it
// with nothing but the URL.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/nobledeveloper01/grid/server/internal/allocation"
	"github.com/nobledeveloper01/grid/server/internal/statement"
	"github.com/nobledeveloper01/grid/server/internal/store"
)

type Server struct {
	store store.Store
	now   func() time.Time
	log   *slog.Logger

	// keys maps an API key to the landlord it belongs to. A map rather than a
	// database table because there is exactly one landlord per deployment
	// today; the moment there are two, this becomes a store method and the
	// handler code does not change.
	keys map[string]string
}

type Options struct {
	Store  store.Store
	Now    func() time.Time
	Logger *slog.Logger
	Keys   map[string]string
}

func New(opts Options) *Server {
	if opts.Now == nil {
		opts.Now = time.Now
	}
	if opts.Logger == nil {
		opts.Logger = slog.Default()
	}
	return &Server{
		store: opts.Store,
		now:   opts.Now,
		log:   opts.Logger,
		keys:  opts.Keys,
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /readyz", s.health)

	// Landlord side — authenticated.
	mux.HandleFunc("POST /v1/statements", s.auth(s.createStatement))
	mux.HandleFunc("GET /v1/statements", s.auth(s.listStatements))
	mux.HandleFunc("DELETE /v1/statements/{id}", s.auth(s.revokeStatement))

	// Tenant side — the token is the authorisation, and there is nothing else.
	mux.HandleFunc("GET /s/{token}", s.viewStatement)

	return logging(s.log, mux)
}

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// auth resolves the landlord from a bearer token.
func (s *Server) auth(
	next func(http.ResponseWriter, *http.Request, string),
) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		key := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		landlord, ok := s.keys[key]
		if key == "" || !ok {
			writeJSON(w, http.StatusUnauthorized,
				map[string]string{"error": "unauthorized"})
			return
		}
		next(w, r, landlord)
	}
}

type createStatementRequest struct {
	PropertyID       string                `json:"property_id"`
	MeterNumber      string                `json:"meter_number"`
	DisCo            string                `json:"disco"`
	PeriodStart      time.Time             `json:"period_start"`
	PeriodEnd        time.Time             `json:"period_end"`
	Rule             allocation.Rule       `json:"rule"`
	TotalKobo        int64                 `json:"total_kobo"`
	TotalEnergyMilli int64                 `json:"total_energy_milli"`
	Occupants        []allocation.Occupant `json:"occupants"`
}

type createStatementResponse struct {
	Statements []issued `json:"statements"`
}

type issued struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	ShareURL   string `json:"share_url"`
	AmountKobo int64  `json:"amount_kobo"`
}

// createStatement splits a period and issues one share link per household.
//
// The split happens **here**, on the server's own copy of the engine, rather
// than trusting figures posted by the client. Not because the landlord's phone
// is untrusted in some adversarial sense, but because the server is what a
// tenant is shown, and a statement whose arithmetic was done somewhere else
// cannot be checked by the party being asked to pay.
func (s *Server) createStatement(w http.ResponseWriter, r *http.Request, landlord string) {
	var req createStatementRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest,
			map[string]string{"error": "malformed body"})
		return
	}
	if len(req.Occupants) == 0 {
		writeJSON(w, http.StatusBadRequest,
			map[string]string{"error": "no occupants to split between"})
		return
	}
	if req.TotalKobo <= 0 {
		writeJSON(w, http.StatusBadRequest,
			map[string]string{"error": "nothing to split"})
		return
	}

	alloc := allocation.Split(
		req.Rule, req.TotalKobo, req.TotalEnergyMilli, req.Occupants,
	)

	// The invariant, checked before anything is issued. If it ever fails the
	// right thing is to refuse rather than to send tenants figures that do
	// not add up.
	if !alloc.SumsExactly() {
		s.log.Error("allocation did not sum exactly",
			"landlord", landlord, "total_kobo", req.TotalKobo)
		writeJSON(w, http.StatusInternalServerError,
			map[string]string{"error": "the split did not balance; nothing was issued"})
		return
	}

	now := s.now()
	out := createStatementResponse{}

	for _, share := range alloc.Shares {
		token, err := statement.NewToken()
		if err != nil {
			writeJSON(w, http.StatusInternalServerError,
				map[string]string{"error": "could not issue a share link"})
			return
		}
		st := statement.Statement{
			ID:          share.Occupant.ID + "-" + now.UTC().Format("20060102150405"),
			Token:       token,
			PropertyID:  req.PropertyID,
			MeterNumber: req.MeterNumber,
			DisCo:       req.DisCo,
			PeriodStart: req.PeriodStart,
			PeriodEnd:   req.PeriodEnd,
			Allocation:  alloc,
			ShareID:     share.Occupant.ID,
			IssuedAt:    now,
			ExpiresAt:   now.Add(statement.DefaultLifetime),
		}
		if err := s.store.PutStatement(r.Context(), landlord, st); err != nil {
			writeJSON(w, http.StatusInternalServerError,
				map[string]string{"error": "could not save the statement"})
			return
		}
		out.Statements = append(out.Statements, issued{
			ID:         st.ID,
			Name:       share.Occupant.Name,
			ShareURL:   "/s/" + token,
			AmountKobo: share.AmountKobo,
		})
	}

	writeJSON(w, http.StatusCreated, out)
}

func (s *Server) listStatements(w http.ResponseWriter, r *http.Request, landlord string) {
	list, err := s.store.StatementsFor(r.Context(), landlord)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError,
			map[string]string{"error": "could not read statements"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"statements": list})
}

func (s *Server) revokeStatement(w http.ResponseWriter, r *http.Request, landlord string) {
	err := s.store.Revoke(r.Context(), landlord, r.PathValue("id"))
	switch {
	case errors.Is(err, store.ErrNotFound):
		// Not a permission error, deliberately: a 403 would confirm that a
		// statement belonging to somebody else exists.
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
	case err != nil:
		writeJSON(w, http.StatusInternalServerError,
			map[string]string{"error": "could not revoke"})
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

// viewStatement is the tenant's entire experience: one URL, no account.
func (s *Server) viewStatement(w http.ResponseWriter, r *http.Request) {
	st, err := s.store.ByToken(r.Context(), r.PathValue("token"), s.now())
	switch {
	case errors.Is(err, store.ErrExpired):
		// Distinct from not-found on purpose. "Ask your landlord for a new
		// link" is actionable; "this does not exist" sends somebody to argue
		// about the wrong thing.
		writeHTML(w, http.StatusGone, expiredPage())
		return
	case err != nil:
		writeHTML(w, http.StatusNotFound, notFoundPage())
		return
	}

	share, ok := st.Share()
	if !ok {
		writeHTML(w, http.StatusNotFound, notFoundPage())
		return
	}

	// A share link is a capability. Keeping it out of caches and out of the
	// referrer header on any link the page carries is the least that owes.
	w.Header().Set("Cache-Control", "no-store, private")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Robots-Tag", "noindex, nofollow")

	writeHTML(w, http.StatusOK, statementPage(st, share))
}

func writeJSON(w http.ResponseWriter, code int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(body)
}

func writeHTML(w http.ResponseWriter, code int, body string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(code)
	_, _ = w.Write([]byte(body))
}

func logging(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		// The path is logged without the token: a share link in a log file is
		// the same disclosure as a share link in a forwarded message.
		path := r.URL.Path
		if strings.HasPrefix(path, "/s/") {
			path = "/s/{token}"
		}
		log.Info("request",
			"method", r.Method,
			"path", path,
			"took", time.Since(start).String(),
		)
	})
}

var _ = context.Background
