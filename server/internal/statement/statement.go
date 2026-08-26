// Package statement turns an allocation into the thing a tenant actually
// receives.
//
// Phase 6's exit gate is one sentence: a tenant opens a statement without
// installing the app. That rules out a mobile deep link, an account, and a
// login — everything that would put a step between the person and the figure
// they are being asked to pay. What is left is a URL that renders a page.
package statement

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"time"

	"github.com/nobledeveloper01/grid/server/internal/allocation"
)

// Statement is one household's share, addressed to them.
type Statement struct {
	ID          string                `json:"id"`
	Token       string                `json:"token"`
	PropertyID  string                `json:"property_id"`
	MeterNumber string                `json:"meter_number"`
	DisCo       string                `json:"disco"`
	PeriodStart time.Time             `json:"period_start"`
	PeriodEnd   time.Time             `json:"period_end"`
	Allocation  allocation.Allocation `json:"allocation"`
	// ShareID identifies which of the allocation's shares this statement is
	// addressed to. The whole allocation travels with it deliberately: a
	// tenant who can see only their own number is being asked to trust the
	// split, and being able to check it is the entire point.
	ShareID   string    `json:"share_id"`
	IssuedAt  time.Time `json:"issued_at"`
	ExpiresAt time.Time `json:"expires_at"`
}

// Share returns the share this statement is addressed to.
func (s Statement) Share() (allocation.Share, bool) {
	for _, sh := range s.Allocation.Shares {
		if sh.Occupant.ID == s.ShareID {
			return sh, true
		}
	}
	return allocation.Share{}, false
}

func (s Statement) Expired(now time.Time) bool {
	return !s.ExpiresAt.IsZero() && now.After(s.ExpiresAt)
}

// DefaultLifetime is how long a share link works for.
//
// Not forever. The link is a capability — anyone holding it can read the
// statement — and a URL that lives in a WhatsApp thread indefinitely is a
// disclosure waiting for the thread to be forwarded. Ninety days covers the
// argument it exists to settle several times over.
const DefaultLifetime = 90 * 24 * time.Hour

// NewToken returns an unguessable share token.
//
// 32 bytes from crypto/rand, base64url. This is the only thing standing
// between a stranger and somebody's electricity statement, so it is not a
// UUID, not a counter, and not derived from anything in the record.
func NewToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generating share token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// Naira formats kobo the way every surface in this product does.
//
// The sign is closed up against the figure with no space at all. The app uses
// a narrow no-break space to keep the crossbars off the first digit, and that
// character is still Unicode whitespace — a PDF renderer broke a line on it and
// printed the sign at the end of one line with the amount at the start of the
// next. HTML would do the same at a narrow width.
func Naira(kobo int64) string {
	negative := kobo < 0
	if negative {
		kobo = -kobo
	}
	// Rounded, not truncated. The Dart formatter rounds, and a statement that
	// reads ₦39,058 beside an app showing ₦39,059 is the exact dispute this
	// product exists to prevent — arriving, this time, from us.
	whole := (kobo + 50) / 100
	s := fmt.Sprintf("%d", whole)

	var out []byte
	for i, c := range []byte(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			out = append(out, ',')
		}
		out = append(out, c)
	}
	if negative {
		return "-₦" + string(out)
	}
	return "₦" + string(out)
}

// Kwh formats milli-kWh to one decimal, rounded in integer space so the last
// inch does not reintroduce the float error the unit exists to avoid.
func Kwh(milli int64) string {
	deci := (milli + 50) / 100
	return fmt.Sprintf("%d.%d kWh", deci/10, abs(deci%10))
}

func abs(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
