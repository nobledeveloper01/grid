# Feature backlog

Fifteen features sourced after phase 3, to widen Grid from *a meter log that produces a
dispute pack* into *the app a Nigerian household opens when anything about electricity goes
wrong*. Each one is written the same way: the problem in the user's words, what Grid would
actually do, what it costs, what it depends on, and the reason it belongs in a product whose
destination is a dispute pack.

Nothing here is scheduled until it has a phase and an exit gate in `docs/ROADMAP.md`. The
phase column below is the commitment; the roadmap is where it becomes checkable.

## How these were chosen

Three filters, applied in order. A feature that fails any one of them is in *Considered and
cut* at the bottom rather than in the list.

1. **Does it survive without a server?** Phases 0–5 are a complete product with no backend.
   A feature that needs one is not disqualified, but it inherits phase 6's risk and has to
   justify it. Eleven of the fifteen need nothing.
2. **Does it make the dispute pack more credible, or does it just make the app bigger?**
   Grid's asset is that its record cannot be quietly rewritten. Features that add *another
   kind of evidence* compound with everything already built. Features that add another
   screen do not.
3. **Is it Nigerian, specifically?** A generic energy tracker already exists in every app
   store and nobody in Lagos uses one. Token vaults, band adherence, vendor effective rates
   and compound meter splits are not features a global product would ever build.

| # | Feature | Backend | Phase |
|---|---|---|---|
| F1 | Token vault and load confirmation | No | 3.5 |
| F2 | Bill capture and reconciliation | No | 4 |
| F3 | Estimated-bill cap check | No | 4 |
| F4 | Band adherence watch | No | 3.5 |
| F5 | Vendor effective-rate watch | No | 3.5 |
| F6 | Many meters, one household | No | 9 |
| F7 | Budget mode against a pay date | No | 4 |
| F8 | Cycle reminders and the reading streak | No | 3.5 |
| F9 | Generator log and blended cost | No | 8 |
| F10 | Solar sizing from measured data | No | 8 |
| F11 | Compound split and the tenant receipt | No | 9 |
| F12 | Appliance coach | No | 8 |
| F13 | Encrypted backup and restore | No | 9 |
| F14 | Home-screen and lock-screen glance | No | 10 |
| F15 | Four more languages and a low-literacy mode | No | 10 |

---

## F1 — Token vault and load confirmation

**Phase 3.5 · No backend · ~3 days**

> "I bought units. The token came by SMS. I typed it, the meter beeped, and I don't know if
> it entered. Then I deleted the message."

A prepaid purchase in Nigeria produces a 20-digit STS token delivered by SMS, and that token
is the only proof the purchase happened. It lives in an inbox that gets cleared, on a phone
that gets changed, from a vendor who does not keep records. When a meter rejects a token —
wrong meter number, already used, expired — the money is gone until somebody can produce the
token, and by then nobody can.

Grid already records purchases. This makes the record complete: the token itself, stored
against the purchase, plus the state of the load. `TokenLoadState` is `entered`, `confirmed`
or `unconfirmed`, and confirmation is not a checkbox — it is the next reading. If a purchase
of 100 kWh is followed by a reading whose balance rose by roughly 100, the load confirmed
itself. If the next reading shows no rise, Grid says so, before the user has forgotten which
vendor sold it.

**Shape.** A `token` field on the purchase fact, formatted in four groups of five so it can
be read aloud to a call centre. A `TokenReconciler` in the domain layer that walks purchases
and readings and classifies each load. A vault screen that is searchable and exportable, and
which is included in the dispute pack when the dispute is about a purchase.

**Depends on** the purchase fact (phase 1) and the balance arithmetic (phase 1). Nothing new.

**Why it belongs.** A dispute about a missing purchase is the second most common electricity
dispute after estimated billing, and Grid currently cannot help with it at all. The token
turns "I bought units" into evidence.

**Care.** A token is a bearer instrument — anyone holding it can load it on the matching
meter. It is stored in the encrypted database like everything else, it is never logged, and
it is redacted from any pack the user has not explicitly chosen to include it in.

---

## F2 — Bill capture and reconciliation

**Phase 4 · No backend · ~5 days**

> "The bill says my meter read 41,208. I have a photograph of it reading 39,940 the same
> week. Nobody at the office will look at both."

This is the whole product, in one screen, for postpaid customers. Grid already photographs
and reads a meter face. A bill is also a rectangle with numbers on it, and the same
`TextRecogniser` façade reads it. What comes out is: the billing period, the opening and
closing readings the DisCo claims, the units billed, the tariff applied, arrears carried
forward, and the total.

Then Grid does the one thing the DisCo's system cannot: it compares the DisCo's claimed
closing reading against the user's own logged reading nearest that date, and it puts the two
numbers next to each other with the photographs underneath.

**Shape.** A `Bill` fact — append-only like everything else, superseded rather than edited.
A `BillReconciler` producing a sealed result: `Agrees`, `Diverges(units, naira, confidence)`,
or `Unreconcilable(reason)` when the user has no reading near enough to the billing date to
say anything honest. That third case matters more than the first two, because an app that
manufactures a divergence out of a fortnight-old reading is worse than useless in front of a
regulator.

**Depends on** OCR (phase 2), and on a reading within a tolerance window of the bill date —
which is exactly what F8 exists to produce.

**Why it belongs.** It converts the dispute pack from *here is my consumption* into *here is
the arithmetic error, in naira*. That is a different conversation.

---

## F3 — Estimated-bill cap check

**Phase 4 · No backend · ~3 days**

> "I have no meter. They send me whatever number they like, every month, and it goes up."

An unmetered customer is billed on estimate, and estimated billing is capped by regulation —
an unmetered customer on a feeder cannot be billed above the average consumption of the
metered customers on that same feeder and band. Most people who are billed above the cap
have never heard of the cap.

Grid computes the cap for the user's band and tariff from its bundled table, compares it to
the bill captured in F2, and states the overage in naira and in units. If the bill is above
the cap, the escalation ladder in phase 5 already knows what to do with it.

**Shape.** A `CapEngine` in the domain layer, fed by the bundled tariff table plus a
cap-basis table shipped alongside it. Output is a sealed `CapVerdict`: `WithinCap`,
`AboveCap(overage)`, `NoCapApplies(reason)` — the last for a metered customer, where an
estimated bill is a different complaint with a different remedy.

**Depends on** F2, and on the bundled tariff table (phase 1).

**Before this ships**, the cap basis and the citation in the user-facing copy must be checked
against the NERC order currently in force, not against what was true when this was written.
Grid quoting a superseded order in a letter to a DisCo would damage the user's case, and the
whole product is a bet that Grid does not do that. This check is part of the exit gate.

**Why it belongs.** Estimated billing is the single most common electricity complaint in
Nigeria, and it is the one where the regulation is most clearly on the customer's side.

---

## F4 — Band adherence watch

**Phase 3.5 · No backend · ~4 days**

> "They moved us to Band A. The bill tripled. The light did not."

Since the service-based bands came in, what a household pays is tied to hours of supply it is
supposed to receive, and a band that is billed but not delivered is a refundable difference,
not a grievance. Grid has, uniquely, the measured other half of that equation — the supply
timeline from phase 3.

This feature does the subtraction. Declared band, its promised daily hours, measured hours,
coverage of the measurement, and the shortfall expressed three ways: hours, percentage, and
the naira value of the tariff difference between the band billed and the band actually
delivered.

**Shape.** A `BandAdherenceEngine` over supply events, reporting per day, per week and per
billing cycle. Every figure carries its coverage, and a period whose coverage is below a
floor reports `InsufficientCoverage` instead of a number. It will be tempting to interpolate
here — a 62%-covered month showing "you got 11.4 hours a day" is a much more satisfying
screen than one showing "not enough measurement to say". The second one is the one that
survives being challenged.

**Depends on** the supply timeline and the honest coverage accounting (phase 3), both done.

**Why it belongs.** It is the strongest single piece of evidence Grid can produce, it is
built almost entirely from work already finished, and no other app has the measurement.

---

## F5 — Vendor effective-rate watch

**Phase 3.5 · No backend · ~2 days**

> "₦5,000 gave me 38 units at that shop and 42 at the one by the junction. Same meter."

Prepaid units are bought from vendors, agents, apps and POS operators, and what arrives in
the meter for ₦5,000 varies. Some of it is legitimate — fixed charges, VAT, debt recovery
deducted at vending. Some of it is not.

Grid already computes an effective rate on every purchase and already flags divergence from
the band tariff. This turns that into a record with a name on it: which vendor, what
effective rate, over how many purchases, trending which way. A small table the user can
show, or simply act on by walking to the other shop.

**Shape.** A vendor label on the purchase fact — free text with autocomplete, because vendor
names in Nigeria are not an enumeration. A per-vendor rollup. A gentle flag when one vendor's
effective rate is persistently worse than the user's own median, which is a fairer baseline
than the gazetted tariff since it already absorbs that user's own fixed deductions.

**Depends on** purchase recording and effective-rate detection (phase 1), both done.

**Why it belongs.** It pays for itself in the first month, in cash, which is the kind of thing
that keeps an app installed long enough to be there when the dispute arrives.

---

## F6 — Many meters, one household

**Phase 9 · No backend · ~4 days**

> "The shop, the house, and my mother's place in the village. I read all three."

Grid assumes one meter. Plenty of users have several, and the ones who have several are
disproportionately the ones who care enough to log readings at all — landlords, shopkeepers,
people managing a parent's account remotely.

**Shape.** Meter becomes a first-class selectable entity rather than a singleton. Every fact
is already keyed by meter, so the schema does not move; what moves is the router, the home
screen, and a combined spend view across meters. The migration is a UI migration, which is
why this sits after the analytics work rather than before it.

**Depends on** nothing new. This is deliberately late — doing it early would have meant every
screen carrying a meter switcher through three phases of churn.

**Why it belongs.** It is the bridge to the landlord console in phase 6 without needing the
backend the console needs. Someone managing four meters offline is already the customer.

---

## F7 — Budget mode against a pay date

**Phase 4 · No backend · ~3 days**

> "I don't need to know when the units finish. I need to know if they finish before the 28th."

The depletion forecast answers the wrong question by one step. A date is only actionable
against another date: when money next arrives. Salary day, market day, the day the rent comes
in.

Grid takes a monthly budget and a pay date, and reframes every forecast against it: *your
units reach zero four days before the 28th; ₦2,300 more this week closes the gap*, or *you
are ₦900 under budget at this burn rate*. The same arithmetic, told as a decision.

**Shape.** A budget as *state*, not a fact — it is a preference, it changes, last write wins.
A `BudgetEngine` reusing the forecast and returning a sealed `BudgetOutlook`:
`OnTrack(headroom)`, `ShortBy(naira, days)`, `Unknown(reason)`. The hero card on the home
screen changes what it leads with once a budget exists.

**Depends on** the forecast engine (phase 1), done.

**Why it belongs.** It is the feature that makes the app worth opening on a day when nothing
is wrong. Everything else in Grid is for the day something is.

---

## F8 — Cycle reminders and the reading streak

**Phase 3.5 · No backend · ~2 days**

> "I logged it religiously for three weeks and then I forgot for two months."

A dispute pack built on readings taken whenever the user happened to remember is weak in a
specific, fixable way: the gaps sit exactly where the other side needs them to. Readings
taken on the same day each cycle, near the DisCo's own billing date, are what make F2's
reconciliation possible at all.

**Shape.** A local notification anchored to the user's billing cycle date, not to an
arbitrary interval — offered once, after the second reading, when the app has enough to
suggest a sensible day. A streak that counts *cycles covered*, not consecutive days, because
consecutive days is a game and cycles covered is the actual evidentiary property. And a
visible, honest gap marker in the history, since a hidden gap is the thing that ambushes
somebody in front of a DisCo officer.

**Depends on** local notifications only. No server, no push infrastructure.

**Why it belongs.** It is the cheapest feature here and it raises the quality of every
figure the app produces. It is also the feature the dispute pack most quietly depends on.

---

## F9 — Generator log and blended cost

**Phase 8 · No backend · ~4 days**

> "Is it cheaper to run the gen for three hours or just wait?"

Nobody in this market consumes only grid electricity. The real household number is blended —
grid units at the band tariff, plus petrol or diesel at whatever it cost this week, plus the
generator's own consumption rate. Households make this trade several times a week and
essentially nobody has the number.

**Shape.** A fuel purchase fact (litres, naira, date) and a run-log (start, stop, which
generator). Divide by the generator's rated consumption to get a naira-per-kWh for generated
power, and show it beside the grid rate. The comparison is stark — generated power typically
costs several times grid power — and it is the first time most users will have seen it.

Run hours can be captured the way supply is: cheaply, from the phone. But the honest version
is a manual start/stop with a running timer, because inferring generator run-time from
charging state on a household that also has mains is guesswork dressed as measurement.

**Depends on** the appliance and load model (phase 4).

**Why it belongs.** It answers a question users ask out loud, weekly, and it makes the case
for F10 out of the user's own money rather than out of a brochure.

---

## F10 — Solar sizing from measured data

**Phase 8 · No backend · ~4 days**

> "Everyone says go solar. Nobody can tell me what size, and every vendor's answer is the
> size they happen to sell."

Solar sizing in Nigeria is done by vendors, on commission, from a guess about the customer's
load. Grid has, by phase 8, months of measured consumption, measured outage hours, and — from
F9 — what the household actually spends on fuel.

**Shape.** Not a generic calculator. A sizing derived from *this household's* measured daily
kWh, its measured outage profile (when the outages fall matters as much as how long they
last), and a battery sizing driven by the longest measured outage rather than the average
one. Payback computed against real logged generator spend, not an assumed figure. And a
plain statement of what the estimate does not know, because the vendor's version will not
have one.

**Depends on** F9, the load model (phase 4), and the supply timeline (phase 3).

**Why it belongs.** It is the natural destination of everything Grid measures, and it is the
first feature where Grid's answer is *better* than the professional's — not cheaper, better,
because it is built on measurement the professional does not have.

---

## F11 — Compound split and the tenant receipt

**Phase 9 · No backend · ~5 days**

> "One meter, five tenants, and every month the same argument about who owes what."

The single meter serving several households is the default in Nigerian rented accommodation,
and the split is done by shouting. Landlords do it by room count, by appliance, by a rule
invented on the spot, and nobody trusts the arithmetic because nobody can see it.

This is the landlord console's job, but the landlord console is phase 6 and needs a server.
This does the ninety-percent version with no server at all: split a period's consumption
across named occupants by an explicit, visible rule, and produce a receipt image per occupant
showing the meter photograph, the period, the total, the rule, and their share — shareable
through WhatsApp, which is where this argument actually happens.

**Shape.** A `SplitRule` — equal, by room count, by weighted load from the appliance
inventory, or a manual percentage — as state, versioned so a past receipt still shows the
rule that produced it. An `AllocationEngine` whose shares sum to the total exactly, to the
naira, enforced by property-based tests. That invariant is already written down as phase 6's
exit gate; this brings it forward, offline, and phase 6 inherits a proven engine.

**Depends on** the consumption engine (phase 1) and the appliance model (phase 4).

**Why it belongs.** It is the highest-frequency dispute in the entire market — monthly, in
every compound — and it is the one Grid can settle before it starts rather than after.

---

## F12 — Appliance coach

**Phase 8 · No backend · ~3 days**

> "Something is eating my units. I don't know what."

Phase 4 models load attribution. This makes it answer a question instead of drawing a chart:
which appliance is costing the most, and what happens to the bill if it runs two hours less.

**Shape.** A ranked attribution with a naira figure against each appliance, and a what-if
that recomputes the month against a changed run-time. Every figure rendered as an estimate —
dashed, tinted, labelled — because it is modelled, not measured, and this is precisely the
screen where a user is most likely to mistake the two.

**Depends on** the load model (phase 4).

**Why it belongs.** It is the return path for the appliance inventory. Without it the
inventory is data entry the user did for the app's benefit rather than their own.

---

## F13 — Encrypted backup and restore

**Phase 9 · No backend · ~4 days**

> "My phone was stolen."

Grid holds two years of evidence in a local database, and an evidence product with no
recovery path is one dropped phone away from having nothing. There is no server until phase
6, and this must not wait for one.

**Shape.** A single encrypted archive — facts, photographs, hashes — with a passphrase the
user sets, written to wherever the platform's file picker points: Files, Drive, a WhatsApp
message to themselves. Restore verifies every integrity hash and reports what did not verify
rather than silently importing it. The archive format is versioned from the first release,
because a backup that a later version cannot read is not a backup.

**Depends on** the integrity hashes (phase 2), done.

**Why it belongs.** It is the difference between a record and a fragile record, and the
product's entire claim rests on the record.

---

## F14 — Home-screen and lock-screen glance

**Phase 10 · No backend · ~4 days**

> "I just want to see how many units are left without opening anything."

**Shape.** A home-screen widget on both platforms — units remaining, days to depletion,
supply state right now — plus a Live Activity on iOS during an outage showing elapsed time,
because an outage is exactly the moment a user wants a running number and exactly the moment
they are least inclined to open an app.

Both platforms need a shared storage container and a small native rendering layer per
platform: this is the one feature here with real per-platform cost, and it is scheduled
accordingly.

**Depends on** the platform façade pattern established in phases 2 and 3.

**Why it belongs.** Retention. A widget is the cheapest reason to keep an app installed
through the months when nothing is going wrong.

---

## F15 — Four more languages and a low-literacy mode

**Phase 10 · No backend · ~6 days**

> "My mother owns the meter. She will not use an app in English."

Grid's user is not only the person who downloaded it. Nigerian Pidgin, Hausa, Yoruba and Igbo
cover the overwhelming majority of the market, and Pidgin in particular is the register in
which most people would naturally discuss this subject.

**Shape.** Full localisation, and — more consequentially — a mode where the numbers carry
the meaning and the words are support: larger figures, iconography for supply state that
already works without colour, and a capture flow that can be completed without reading a
sentence. That last constraint is nearly satisfied already, because the outdoor-at-night
design pressure pushed the same way.

Translation is not a `.arb` file run through a machine. Tariff bands, estimated billing and
depletion dates are terms with settled local phrasing, and getting them wrong reads as an
app that does not know the country. This needs a translator, and the schedule reflects that.

**Depends on** copy stability across every screen — which is why it is last.

**Why it belongs.** It is the difference between an app for people who read English
comfortably and an app for the market.

---

## Considered and cut

Five that did not make the fifteen, and why — kept here because the reasoning will be needed
again the next time somebody suggests them.

**Neighbour cross-check.** Two households on one feeder compare supply timelines to prove an
outage was the feeder rather than the house. Genuinely powerful evidence, and it works
offline through a shared signed blob. Cut for now because a timeline received from another
device is a fact Grid did not observe, and the append-only model has no honest place to put
it yet. Revisit after phase 6, when there is a trust model to hang it on.

**Meter accuracy self-audit.** Compare implied consumption against modelled appliance load
and flag a meter that may be running fast. Cut because the load model reconciles to within
25% and a meter-accuracy accusation needs far better than that. Grid would be sending users
into a formal process on a number it knows is soft.

**Load-shedding roster adherence.** Capture the published feeder roster and measure against
it. Cut because rosters are published inconsistently and often not honoured even when
published, which makes the comparison a measurement of a document rather than of service.
F4 measures the thing that actually carries a remedy.

**Metering application tracker.** Track a MAP or mass-metering application with follow-up
dates and an escalation path. Genuinely useful, genuinely a different product — it is a case
tracker, not a meter log, and phase 5's escalation ladder is where it would belong if it
belongs anywhere.

**In-app vending.** Buy units inside Grid. Cut on principle. The moment Grid takes a margin
on a purchase, its effective-rate warnings are no longer disinterested, and disinterest is
the only thing the dispute pack is actually built on.
