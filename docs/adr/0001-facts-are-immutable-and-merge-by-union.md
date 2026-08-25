# ADR-0001 — Facts are immutable and merge by union; state is last-writer-wins on a hybrid logical clock

**Status:** accepted
**Date:** 2026-08-25

## Context

Grid's destination is a dispute pack: a document that makes a distribution company back
down. Everything before it — readings, photographs, supply logs — exists to make that
document credible.

The product is also offline-first by necessity. A user may be disconnected for weeks, and
from v1.1 a landlord's phone and a tenant's phone will both hold copies of overlapping data.
Two devices will edit while neither can see the other.

The obvious model is the one every CRUD app uses: rows that get updated in place, resolved
last-writer-wins when they eventually sync. It fails here twice over.

**It destroys evidence.** A reading that can be updated is a reading that can be quietly
changed after the fact. That is not a data-integrity concern in the abstract — it is the
specific reason a DisCo's lawyer would dismiss the pack. "How do we know this log wasn't
edited last week?" has no good answer if the schema permits editing.

**It loses data on merge.** Two devices recording readings for the same meter during a
partition produce two sets of rows. Last-writer-wins picks one and discards the other. Both
readings were real observations of a physical meter; discarding either is fabricating
history.

## Decision

Two classes of data, with different rules.

**Facts** — readings, purchases, supply events. Append-only, immutable, keyed by a
client-generated UUID v7. Never updated. Never deleted. A correction writes a *new* fact
and sets `superseded_by` on the original; the original keeps its value, its photograph and
its timestamp forever. Merge is **set union by id** — there is no conflict to resolve,
because a reading taken on Tuesday and a reading taken on Wednesday are both true.

**State** — meter configuration, appliance inventory, settings. Mutable, resolved
last-writer-wins on a hybrid logical clock, with `node_id` breaking ties deterministically
so every device reaches the same answer.

Device clocks in this market are frequently wrong — sometimes by days, and a flat battery
resets them. The HLC (`physical_ms`, `counter`, `node_id`) preserves causal ordering
regardless: an event created after another always orders after it, even when the device
believes otherwise.

## Consequences

**What it buys.** Offline sync becomes almost trivial for the data that matters: facts
union, and a client that has been offline for six weeks pushes six weeks of rows in any
order and converges correctly. There is no transaction semantics to get wrong, no ID
remapping, and no ordering requirement between pushes. The audit trail is complete by
construction rather than by discipline.

**What it costs.** The schema is larger — superseded rows accumulate and are never
reclaimed. Queries must filter `superseded_by IS NULL` on every read path, and forgetting
to is a real bug class. Storage grows monotonically, which the retention policy manages for
photographs but not for rows.

**What it forbids.** There is no "fix this reading" affordance anywhere in the product, and
there cannot be one. Users will ask for it. The answer is a correction that supersedes,
which is more clicks and less obvious — and it is the whole reason the pack is worth
anything.

**What a future reader might want to reverse.** Hard-deleting old superseded rows to
reclaim space. Doing so is safe only for rows that have never appeared in a generated
dispute pack, and nothing currently records that. Add it before reclaiming anything.
