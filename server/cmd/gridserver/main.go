// Command gridserver issues tenant statements and serves them.
//
// Phase 6 of Grid. Everything the phone does is offline and stays offline;
// this exists for one reason, stated in the roadmap before any of it was
// written: a second person has to be able to read what the first person
// recorded. A tenant needs to see their share, and they should not have to
// install an app to do it.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/nobledeveloper01/grid/server/internal/api"
	"github.com/nobledeveloper01/grid/server/internal/store"
)

func main() {
	// The image is `scratch`: no shell, no curl, nothing for a container
	// healthcheck to call. So the binary checks itself, which is also the
	// only version of the check that cannot drift from what the server
	// actually serves.
	healthcheck := flag.Bool("healthcheck", false,
		"probe the local server and exit non-zero if it is not ready")
	flag.Parse()

	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	addr := env("GRID_ADDR", ":8080")

	if *healthcheck {
		os.Exit(probe(addr))
	}

	// Keys are `landlord:key` pairs. One landlord per deployment today, so a
	// map from the environment beats a table nobody would have a second row
	// in — and when there is a second, this becomes a store method and no
	// handler changes.
	keys := parseKeys(env("GRID_API_KEYS", ""))
	if len(keys) == 0 {
		log.Warn("no GRID_API_KEYS set — the landlord API will reject everything. " +
			"Tenant links still work; they are authorised by the token alone.")
	}

	st := store.NewMemory()
	defer func() { _ = st.Close() }()

	srv := &http.Server{
		Addr: addr,
		Handler: api.New(api.Options{
			Store:  st,
			Logger: log,
			Keys:   keys,
		}).Routes(),
		// A tenant on 3G is the slow client this is sized for; a landlord
		// posting a split is not.
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		log.Info("listening", "addr", addr)
		if err := srv.ListenAndServe(); err != nil &&
			!errors.Is(err, http.ErrServerClosed) {
			log.Error("server stopped", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	// A tenant halfway through loading their statement should get the whole
	// page rather than a reset connection.
	log.Info("draining")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Error("drain did not finish", "error", err)
	}
	log.Info("stopped")
}

// probe hits /healthz on the local listener. Returns a process exit code.
func probe(addr string) int {
	host := addr
	if strings.HasPrefix(host, ":") {
		host = "127.0.0.1" + host
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://" + host + "/healthz")
	if err != nil {
		return 1
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// parseKeys reads "landlord:key,landlord2:key2".
func parseKeys(raw string) map[string]string {
	out := map[string]string{}
	for _, pair := range strings.Split(raw, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		landlord, key, ok := strings.Cut(pair, ":")
		if !ok || landlord == "" || key == "" {
			continue
		}
		// Keyed by the secret, because that is what a request arrives with.
		out[key] = landlord
	}
	return out
}
