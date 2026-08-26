# ADR-0010 — Alerts are raised in the foreground, and say so

**Status:** accepted
**Date:** 2026-08-26

## Context

Phase 3's exit gate asks for band-compliance alerting with hysteresis: no alert
fires twice inside fourteen days for one meter. The obvious reading of "alert"
is a push notification, and the obvious implementation is to evaluate
compliance on a schedule and notify when it crosses the threshold.

That implementation does not exist here, because the thing it depends on does
not. ADR-0003 puts the whole product on the device with no server, so there is
nothing to push from. ADR-0006 and the supply monitor already establish that
neither platform will keep a process alive to watch anything: iOS offers no
background execution that fits, and Android will kill the process. Every
supply event Grid records carries `periodic` or `foregroundOnly` for exactly
this reason.

So compliance can only be evaluated when the app is open. A local notification
raised at that moment is being shown to somebody who is already looking at the
screen — and on iOS it is not even shown, because the system suppresses a
local notification presented while its own app is in the foreground unless the
presentation options explicitly say otherwise. The first implementation of this
fired, recorded its cooldown, and displayed nothing at all.

The tempting alternative is to schedule a repeating local notification that
*assumes* the shortfall persists — fire every fortnight while the last known
state was a breach. That would produce an alert about a condition nobody
measured, on a device that has not opened the app since. It is the same
mistake as interpolating unobserved supply into whichever state is convenient,
one layer up.

## Decision

The **in-app banner is the alert**. It is a status: it reflects the compliance
figure as currently measured, it appears whenever `canRaiseAlert` is true, and
it disappears when the figure recovers. It carries no cooldown, because a
status is not an interruption and hiding a true one for a fortnight would be a
lie of omission.

A **local notification is raised alongside it, best-effort**, when the app is
open and permission has already been granted. It never prompts for permission
— a band-shortfall alert that raises a permission dialogue out of nowhere
teaches the user to deny it, and the permission is worth more than the alert.
The Darwin presentation options are set explicitly so it is not swallowed.

`ComplianceEngine.shouldAlert` and its fourteen-day cooldown govern **only the
notification**. `lastAlertedAt` is written *before* the notification is shown,
so a failure to display still starts the cooldown: a missed alert is better
than a loop that retries on every rebuild.

Nothing in the product claims an alert will reach a user who is not using it.

## Consequences

The gate is met on the terms the architecture can actually support, and the
product does not acquire a promise it cannot keep. A user who stops opening
Grid stops being told about their supply, which is the honest behaviour for an
app with no background execution and no server.

The cost is that the most valuable moment for this alert — a household that
has drifted away and would come back if prodded — is exactly the one Grid
cannot reach. That is a real gap and it is left open rather than papered over.

Phase 6 adds a server, and that is the phase in which this becomes reversible:
with sync there is somewhere to evaluate compliance that is not the user's
phone, and a genuine push becomes possible. A future reader reversing this
should be clear that they are also taking on the obligation ADR-0006 sets —
the server may only alert on periods the device actually observed, and a push
that fires from an assumption is worse than no push at all.
