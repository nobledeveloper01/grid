package api

import (
	"fmt"
	"html"
	"strings"

	"github.com/nobledeveloper01/grid/server/internal/allocation"
	"github.com/nobledeveloper01/grid/server/internal/statement"
)

// The tenant-facing pages.
//
// Server-rendered HTML with the CSS inline and no JavaScript at all. The
// audience opens this on a mid-range Android over a metered connection, quite
// possibly on 3G, and every kilobyte is a kilobyte they paid for. It also
// means the page works with JavaScript disabled, in a WhatsApp in-app browser,
// and in whatever a two-year-old handset ships as a default.
//
// Everything interpolated is escaped. The occupant names come from a landlord
// typing into a phone, which is exactly the kind of input that eventually
// contains an angle bracket.

const style = `
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
  margin: 0; padding: 24px 16px 48px;
  font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: #14110C; color: #F5F0E8;
}
main { max-width: 34rem; margin: 0 auto; }
.eyebrow { font-size: 12px; letter-spacing: 1.4px; color: #FFB020; margin: 0 0 6px; }
h1 { font-size: 26px; margin: 0 0 4px; font-weight: 600; }
.period { color: #A69B8A; margin: 0 0 24px; }
.amount {
  background: linear-gradient(135deg, #F59E0B, #E07B00);
  color: #1A1206; border-radius: 20px; padding: 22px; margin-bottom: 22px;
}
.amount .figure { font-size: 38px; font-weight: 700; letter-spacing: -0.5px; }
.amount .units { opacity: .8; }
.card {
  background: #1E1A14; border: 1px solid #2E281F;
  border-radius: 16px; padding: 18px; margin-bottom: 16px;
}
h2 { font-size: 12px; letter-spacing: 1.2px; color: #FFB020; margin: 0 0 10px; font-weight: 600; }
table { width: 100%; border-collapse: collapse; font-size: 15px; }
th, td { text-align: left; padding: 9px 0; border-bottom: 1px solid #2E281F; }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
tr.total td { border-bottom: none; font-weight: 600; }
tr.you { color: #FFB020; font-weight: 600; }
.note { color: #A69B8A; font-size: 14px; margin: 10px 0 0; }
.check { color: #6FCF97; font-size: 14px; margin: 10px 0 0; }
.foot { color: #6E6455; font-size: 13px; margin-top: 28px; }
`

func page(title, body string) string {
	return `<!doctype html><html lang="en"><head>` +
		`<meta charset="utf-8">` +
		`<meta name="viewport" content="width=device-width, initial-scale=1">` +
		`<meta name="robots" content="noindex, nofollow">` +
		`<title>` + html.EscapeString(title) + `</title>` +
		`<style>` + style + `</style></head><body><main>` + body +
		`</main></body></html>`
}

func statementPage(st statement.Statement, share allocation.Share) string {
	var rows strings.Builder
	for _, s := range st.Allocation.Shares {
		cls := ""
		if s.Occupant.ID == st.ShareID {
			cls = ` class="you"`
		}
		fmt.Fprintf(&rows,
			`<tr%s><td>%s</td><td class="num">%s</td><td class="num">%s</td></tr>`,
			cls,
			html.EscapeString(s.Occupant.Name),
			html.EscapeString(basisOf(st.Allocation.Rule, s)),
			html.EscapeString(statement.Naira(s.AmountKobo)),
		)
	}

	check := `<p class="check">These shares add up to the meter total exactly.</p>`
	if !st.Allocation.SumsExactly() {
		check = `<p class="note">These shares do not sum to the meter total.</p>`
	}

	remainder := ""
	if st.Allocation.RemainderGivenTo != "" {
		remainder = fmt.Sprintf(
			`<p class="note">A few kobo would not divide evenly and were `+
				`added to %s's share.</p>`,
			html.EscapeString(st.Allocation.RemainderGivenTo),
		)
	}

	body := fmt.Sprintf(`
<p class="eyebrow">ELECTRICITY SHARE</p>
<h1>%s</h1>
<p class="period">%s to %s</p>

<div class="amount">
  <div class="figure">%s</div>
  <div class="units">%s of the meter total</div>
</div>

<div class="card">
  <h2>HOW THIS WAS WORKED OUT</h2>
  <p style="margin:0 0 12px">%s. %s</p>
  <table>
    <tr><th>Household</th><th class="num">Basis</th><th class="num">Share</th></tr>
    %s
    <tr class="total"><td>Meter total</td><td class="num"></td><td class="num">%s</td></tr>
  </table>
  %s
  %s
</div>

<div class="card">
  <h2>THE METER</h2>
  <p style="margin:0">%s · %s</p>
  <p class="note">Readings were taken at the meter itself, on the dates the
  landlord recorded them. If a figure here looks wrong, this page is what to
  ask about — it shows the whole split, not only your part of it.</p>
</div>

<p class="foot">Issued %s. This link stops working on %s. Prepared with Grid.</p>
`,
		html.EscapeString(share.Occupant.Name),
		st.PeriodStart.Format("2 January 2006"),
		st.PeriodEnd.Format("2 January 2006"),
		html.EscapeString(statement.Naira(share.AmountKobo)),
		html.EscapeString(statement.Kwh(share.EnergyMilli)),
		html.EscapeString(st.Allocation.Rule.Label()),
		html.EscapeString(st.Allocation.Rule.Description()),
		rows.String(),
		html.EscapeString(statement.Naira(st.Allocation.TotalKobo)),
		check,
		remainder,
		html.EscapeString(nonEmpty(st.MeterNumber, "Meter number not recorded")),
		html.EscapeString(nonEmpty(st.DisCo, "Distribution company not recorded")),
		st.IssuedAt.Format("2 January 2006"),
		st.ExpiresAt.Format("2 January 2006"),
	)

	return page(share.Occupant.Name+" — electricity share", body)
}

func expiredPage() string {
	return page("Link expired", `
<p class="eyebrow">ELECTRICITY SHARE</p>
<h1>This link has expired</h1>
<p class="period">Share links stop working after 90 days.</p>
<div class="card">
  <p style="margin:0">Ask whoever sent it to issue a new one. Nothing has been
  deleted — the statement still exists, this particular link just no longer
  opens it.</p>
</div>`)
}

func notFoundPage() string {
	return page("Not found", `
<p class="eyebrow">ELECTRICITY SHARE</p>
<h1>Nothing here</h1>
<div class="card">
  <p style="margin:0">This link does not open a statement. Check it was copied
  in full — they are long, and messaging apps sometimes break them across two
  lines.</p>
</div>`)
}

func basisOf(rule allocation.Rule, s allocation.Share) string {
	switch rule {
	case allocation.ByRooms:
		if s.Occupant.Rooms == 1 {
			return "1 room"
		}
		return fmt.Sprintf("%d rooms", s.Occupant.Rooms)
	case allocation.ByLoad:
		return fmt.Sprintf("%.0f units", s.Basis)
	case allocation.Manual:
		return fmt.Sprintf("%.0f", s.Basis)
	default:
		return "equal"
	}
}

func nonEmpty(v, fallback string) string {
	if strings.TrimSpace(v) == "" {
		return fallback
	}
	return v
}
