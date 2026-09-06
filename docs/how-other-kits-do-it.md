# How the other build kits implement a slice

Read the code, not the descriptions: every kit in the CLI's own source, plus the
two community ones. What follows is what each actually does, where we differ,
and the three things worth taking.

> **Researched 06·09·2026** against `Nebulit-GmbH/Eventmodelers-Build-Kits` and
> `gklijs/skilj-build-kit`.

---

## The landscape

| Kit | Store | Write boundary | Read model |
|---|---|---|---|
| **node** | Postgres via Emmett | **stream per aggregate** | **materialised** — table + SQL migration |
| **supabase** | Postgres via Emmett | stream per aggregate | materialised — table + migration |
| **axon** | Axon Server | aggregate | materialised |
| **kurrent** | KurrentDB | stream | materialised |
| **opencqrs** | EventSourcingDB | stream | materialised |
| **umadb** | UmaDB | **DCB** | materialised |
| **cratis** | Cratis | aggregate | materialised |
| **skilj** *(community)* | Postgres | **DCB** | materialised |
| **this kit** | FACT (files) | **DCB** | **folded on read** |

Two clean splits, and we're on the minority side of both — deliberately on one,
and alone on the other.

---

## The write path: three of us do DCB

**node and supabase are stream-per-aggregate.** The command handler is
`CommandHandler(eventStore, id, decide)` — the `id` *is* the stream — and
concurrency is a `nextExpectedStreamVersion`. Classic Decider: `decide`,
`evolve`, `initialState`, tested with `DeciderSpecification`.

**umadb, skilj and this kit are DCB**, and the shape is the same in all three:

| | umadb | skilj | this kit |
|---|---|---|---|
| scope the read | `Query` on id tags | `tag_mappings()` | `Core.query/1` |
| fold | `DecisionModelLoader.load` | `decide(payload, matching_events)` | `read_and_fold/3` |
| append condition | `AppendCondition.failIfExistsAfter` | DCB condition | `append_condition/1` + `last_position` |
| on conflict | fails the append | **retries** | **retries** |

So the pattern isn't ours; it's the emerging one for stores that support it.
What differs is how the tags get *found* — and there we're the outlier in the
other direction, see below.

**One thing we have that none of them mentions:** `esperar_visibilidad/3`. FACT
confirms an append 7–10 ms before the event is visible to a subsequent read, and
a LiveView that writes and immediately re-reads would paint stale. We wait,
once, in the single place every write passes through. Whether the others need it
depends on their store; none says.

---

## The read path: we are alone

Everyone else **materialises**. node and supabase write a Postgres table with a
numbered SQL migration per state-view slice. skilj is explicit about the
contrast, and describes us without naming us:

> skilj's own `Projection` *is* materialised (a real `projection_state` row,
> updated as events arrive) — it isn't recomputed on every query the way a
> "fold on the fly" read model in a framework with no built-in projection
> concept would be.

That's exactly what we do, and it isn't an oversight: FACT has no projection
concept, so a read model is a fold over tag-scoped events, computed per request.

**What it buys us.** No migrations. No rebuild or replay machinery. No
possibility of drift — the read model *is* the events, so it can't disagree with
them. Adding a read model is writing a function.

**What it costs.** Every read pays the fold, and the cost grows with the number
of events carrying that tag. There's no SQL over a read model. It works because
tags are narrow: a plot check reads a handful of events. **It would not survive
a tag with a million events behind it**, and the day one appears we need a
materialised projection with no framework to lean on.

Worth writing down as a known ceiling rather than discovering it later.

---

## Three things worth taking

### 1. Teach how tags are found, not just the rule

Ours is mechanical, and that's a genuine advantage: `slice.json` already carries
`idAttribute: true`, so the board author made the modelling decision and the
agent invents nothing. skilj can't do that — nothing in their pipeline marks it
— so they hand the agent a *question* instead:

> "If a different command's own decision needed to know about this, what
> field's value would it match on?"

…plus a worked example of the case a single aggregate ID can't express:
enrolling a student in a course, tagged on **both** `student` and `course`, so
one `decide()` sees both histories and checks both invariants atomically — no
saga, no reservation, no compensation.

We don't need their derivation, but we should carry their *reasoning*, because
our rule has an escape hatch: "if an event has no `idAttribute: true`, stop and
invoke `request-feedback`". When that fires, the human being asked has no
guidance on what to answer. The question above is that guidance.

### 2. `references/` under a skill

skilj and axon factor deep stack knowledge into `references/` beside each skill
— `dcb-tags.md`, `command-type.md`, `common-mistakes.md`, `projection.md`. The
skill then covers only board→code translation and says "skim the reference
first".

Ours puts everything in `CLAUDE.md` plus the skills, which is why
`build-state-change` runs to 345 lines. Splitting would keep each skill about
translation and let the FACT-specific material grow without bloating it.

### 3. Board comments, in every skill

node instructs the agent to read each element's `comments[]` as implementation
hints **and resolve them afterwards** — in all three skills. We only do it in
`build-state-change`, so a state-view or automation slice with comments on it
has them silently ignored and never resolved.

A real hole, and a cheap fix.

---

## Where ours is better

**The board's own metadata decides the tags.** Mechanical, deterministic, and
the failure mode is loud: a missing `idAttribute` stops the build and asks a
human instead of letting the agent guess a consistency boundary.

**No migrations anywhere.** A state-view slice is a function; no numbered SQL
file, no ordering problem, no rebuild path to maintain.

**Read-your-writes is solved once**, in `Decide`, instead of left to each caller
to rediscover.

**And the screen boundary is explicit.** No other kit writes a *screen brief*.
The others either ignore the UI or generate it; we produce a document that says
what the read model gives and — the part that earns its keep — **what it does
not**, so whoever builds the view can't invent fields.

## Applied, 06·09·2026

All three, plus a fourth the research surfaced:

- Board comments now in **all four** skills, not one.
- A `references/` layer: `finding-tags.md` under build-state-change,
  `materialised-projections.md` under build-state-view.
- The tag *reasoning* — the question to put to a modeller when the mechanical
  rule runs out, and the two-tag case a single aggregate id can't express.
- **The escape hatch that was genuinely missing.** Fold-on-read having a
  ceiling with nowhere to go was the sharpest finding here, and the answer
  already existed in `contextovnzla`: a disposable SQLite mirror with the
  checkpoint stored in the same database as the projection, so deleting it
  replays from zero on the next boot — rebuild and start are one path. Written
  up with the four rules that each close a specific hole, and with the line
  that separates a projection from domain.

## Where ours is still weaker

**We ship the largest scaffold** — 49 files against 13–31 — because Phoenix
brings an asset pipeline. Same order as cratis, but the maintenance is real:
`mix phx.new`'s output ages with every Phoenix release.
