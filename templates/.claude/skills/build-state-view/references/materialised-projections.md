# When folding on read isn't enough

**Don't reach for this by default.** A read model in this stack is a fold over
tag-scoped events, computed per request. No table, no migration, no rebuild
path, and no way for the read model to disagree with the events — because it
*is* the events. Every other build kit materialises; we don't, and for the
shapes a board usually produces that's the better trade.

This file is the escape hatch, and the conditions for using it.

## When it stops working

The fold costs O(events carrying that tag), per read. That's nothing while tags
stay narrow — one plot, one check, one order. It stops being nothing when:

- a tag accumulates events without bound (an append-only log per tenant, a
  counter that ticks all day), or
- the query is genuinely relational — "every plot in this state, ordered by
  date, paginated" — which a fold can't express and SQL can, or
- one read has to span many tags at once, so there is no narrow query to scope.

**Measure before concluding.** A fold over a few hundred events is microseconds.
The point at which this matters is further away than it feels.

## The shape, when you do need it

The pattern is a **mirror**: a disposable SQL store beside the event store,
never a source of truth. `Ecto` with `ecto_sqlite3` — no database server, which
keeps the stack's one real promise intact.

```
lib/my_app/mirror/
  repo.ex          the only Ecto in the app
  projection.ex    one row per projection: name, position, updated_at
  projector.ex     a GenServer subscribed to FACT
  <thing>.ex       the schema being projected
```

### Four rules, and each one closes a specific hole

**The projector listens; it is never told.** Write slices do not write to the
mirror. Having a `Context` append and then insert couples a domain decision to a
disposable store — and opens a gap: if the process dies between the two, the
fact is in FACT and not in the mirror, and nobody knows.

**The checkpoint advances only after the write lands.** Then there is no gap to
open. A crash mid-way replays from the last event actually applied.

**The checkpoint lives in the same database as the projection.** Delete the
mirror and both go together, so the next boot replays the whole history.
*Rebuild and start are the same path* — which means there aren't two paths to
keep in sync, and no rebuild step anyone can forget to run.

**Applying twice must be harmless.** Upsert against the primary key, and a
delete that doesn't complain when there's nothing there. Then a checkpoint that
lags is a non-event. Skipping an event is the real danger, which is why the
order is write-then-advance and never the reverse.

### The line not to cross

The mirror is **disposable**: delete it and nothing is lost, because what is
irreplaceable lives in the event store. That is the test of whether something
belongs here.

The day someone wants to add a column that records a human decision — `reviewed`,
`approved_by` — that is domain, and it goes to FACT as an event. A projection
that can't be dropped and rebuilt isn't a projection any more, and the stack
stops being able to tell you what happened.

## Wiring

```elixir
# mix.exs
{:ecto_sql, "~> 3.12"},
{:ecto_sqlite3, "~> 0.17"},
```

```elixir
# aliases — the mirror gets its own setup, and `test` needs it too
"mirror.setup": ["ecto.create --quiet", "ecto.migrate"],
test: ["fact.setup", "ecto.create --quiet", "ecto.migrate --quiet", "test"],
```

The projector subscribes with `Fact.subscribe/3` and `position:` from the stored
checkpoint, which replays from there and then goes live.
