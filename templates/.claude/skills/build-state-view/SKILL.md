---
name: build-state-view
description: Implements a read slice (a read model folded from events, no tables and no materialised projections) in Elixir with the FACT event store, from a slice.json
---

# Build a read slice

> Before anything else, read the definition at
> `.build-kit/.slices/{Context}/{slice}/slice.json`. That file is the **source of
> truth** for every field and every piece of metadata. Never invent fields that
> aren't there.

> **A read model here is a fold, not a table.** No projection, no migration, no
> rebuild path — the read model *is* the events. That's the default and it's
> what to build. If the slice genuinely can't be served that way, read
> `references/materialised-projections.md` before inventing anything: it has the
> conditions, the mirror pattern, and the line that separates a projection from
> domain.

> **Comments**: every element carries `comments: string[]`. Use them as hints.
> If a comment raises an **open decision** rather than a hint — "rate limiting
> still undecided", "own stream or the main registry?" — don't decide it
> yourself: invoke `request-feedback`. Resolve the ones you consume:
> `POST <BASE_URL>/api/org/<ORG_ID>/boards/<BOARD_ID>/nodes/<nodeId>/comments/<commentId>/resolve`.

> And read `.build-kit/CLAUDE.md`, especially the tag rule: this is where it pays
> off or breaks.

---

## What a read slice is

A view that is **folded on the fly from the events**. In this stack there is **no
migration, no table, no materialised projection**: you read and reduce.

```
Context.function(args)  →  Reader.read(db, Core.query(args))
                        →  Enum.reduce(events, Core.initial_state(), &Core.apply_event/2)
                        →  shape the result
```

Two files, not four: `core.ex` and `context.ex`. No command, no event.

---

## Step 1 — Read the `slice.json`

- **`readmodels[]`** and their `fields[]`. Look at:
  - `mapping: "<Event>.<field>"` → **direct copy** when folding that event.
  - `mapping: "derived:…"` → **computed on read**. The prose says how.
  - `optional: true` → the event that carries it hasn't arrived yet.
  - `generated: true` → derived, comes from no event.
  - `cardinality: "List"` with `subfields` → a list of maps.
- **`specifications[]`** — the `given` are the events, the `then` is the expected
  state. **The scenario's `examples` are the final state**, and they're what goes
  into the test.
- **The read model's `description`** — it says what's computed and what's copied,
  and usually justifies why. Read all of it before writing anything.

---

## Step 2 — `core.ex`

**File:** `lib/my_app/slices/<slice>/core.ex`

```elixir
defmodule MyApp.Slices.<Slice>.Core do
  @moduledoc """
  <What this view answers, and what it's scoped by. And what it does NOT
  answer — there's usually a similar view with a different scope, and confusing
  them is the classic mistake.>
  """

  @behaviour MyApp.StateView

  @impl true
  def query(<key>) do
    Fact.QueryItem.types(["<EventA>", "<EventB>"])
    |> Fact.QueryItem.tags(["<entity>:#{<key>}"])
  end

  @impl true
  def initial_state, do: %{field: nil, list: []}

  @impl true
  def apply_event(state, %{"event_type" => "<EventA>", "event_data" => d}) do
    %{state | field: d["field"]}
  end

  def apply_event(state, _), do: state
end
```

Note `@behaviour` and not `use`: `StateView` injects nothing.

### The query names EVERY type the view needs

This is the expensive failure of this slice shape. If the read model folds three
event types, `query/1` has to name all three. A missing one breaks nothing — it
leaves a field `nil` forever.

Derive the list from the fields' `mapping:` values — **and read the prose ones
too**.

Two shapes appear there, and only the first is structured:

```
mapping: "ComprobacionSolicitada.geometria"                    ← <Event>.<field>
mapping: "derived:presencia de DeforestacionEvaluadaConWhisp"  ← event name in a sentence
```

The second is the one that gets missed. A `derived:` mapping whose derivation is
*the presence of an event* still needs that event in `query/1`, and the type name
is buried in a human-written phrase rather than in a field of its own.

So don't pattern-match on `<Event>.<field>`. **Scan every `mapping` value — both
shapes — for any event name that exists in this context**, and put every one you
find in `query/1`. The context's event names are a known, closed list, so this is
a lookup, not a guess.

And don't lean on `events[]` for a state-view slice: on a read slice it is
routinely **empty**, because the events belong to the write slices that emit
them. `mapping` is the only place they appear.

### The tag scopes the view

`Fact.QueryItem.tags(["check:#{id}"])` answers "how is **this one** doing".
`tags(["session:#{id}"])` answers "what did **I** ask for". Different views even
though they fold the same events, and the board usually has both.

The tag comes from the same rule as on the write side: fields with
`idAttribute: true`. If you don't know which one scopes this view, look at which
read model field is the `idAttribute`.

**Exception: a TODO queue isn't scoped by tag.** Its consumer is a processor,
which has no session or any other identity to filter by. The query goes by types
alone, and that's correct — say so in the `@moduledoc` so nobody "fixes" it.

### Derived means computed here, not stored

A field with `mapping: "derived:presence of <Event>"` is
`%{state | status: "resolved"}` inside that event's `apply_event/2`. A `derived:`
that combines several is computed at the end, in `context.ex`.

**Never store on the event something you can derive on read.** If it feels like a
field is missing, it almost always needs deriving.

### Lists

With `cardinality: "List"` the state carries a list and `apply_event/2` extends
it. Order it explicitly in `context.ex` — the arrival order is log order, which
may not be what the screen wants.

---

## Step 3 — `context.ex`

```elixir
defmodule MyApp.Slices.<Slice>.Context do
  @moduledoc "Public API of <the view>."

  alias MyApp.Slices.<Slice>.Core

  def <verb>(<key>) do
    MyApp.Application.fact_db()
    |> MyApp.Reader.read(Core.query(<key>))
    |> Enum.reduce(Core.initial_state(), &Core.apply_event(&2, &1))
    |> shape()
  end

  defp shape(state), do: state
end
```

**Always `MyApp.Reader.read/2`, never `Fact.read/2`.** `Reader` picks an index
instead of scanning the whole ledger; the difference is three orders of magnitude
once history grows.

`shape/1` is where the derived values that combine several events go, and where
lists get ordered. No presentation formatting: formatted strings, translated
text and rendering decisions belong to the screen, not the model.

---

## Step 4 — `core_test.exs`

**File:** `test/my_app/slices/<slice>/core_test.exs`

```elixir
defmodule MyApp.Slices.<Slice>.CoreTest do
  use ExUnit.Case, async: true

  alias MyApp.Slices.<Slice>.Core

  defp fold(events),
    do: Enum.reduce(events, Core.initial_state(), &Core.apply_event(&2, &1))

  defp ev(type, data \\ %{}), do: %{"event_type" => type, "event_data" => data}

  describe "<the specification's literal title>" do
    test "<what it pins down>" do
      state = fold([ev("<EventA>", %{"field" => "value"})])
      assert state.field == "value"
    end
  end
end
```

- **Only the pure `Core`**, no store and no `Context`.
- **The data comes from the scenario**: the `given` are the events, and the
  scenario's `examples` is the expected state.
- **Test the initial state**: a read model with no events has to be renderable,
  not blow up. The screen will paint it while the rest arrives.
- **Test arrival order** if the view folds several flows that arrive with no
  guaranteed order. Two events one way and the other way must give the same
  result, or the system has a race.
- **Test that `apply_event/2` ignores what isn't its own**: a type that isn't
  hers must not change the state.
- **Never compare `Map.keys/1` against a list.** The order **isn't guaranteed**
  and the assertion fails intermittently — it passes locally and breaks the gate
  later. To pin down a row's keys:

  ```elixir
  assert MapSet.new(Map.keys(row)) == MapSet.new([:a, :b, :c])
  ```

  Same goes for any comparison of collections with no defined order.

---

## Step 5 — Quality gate

```
mix precommit
mix test test/my_app/slices/<slice>/
```

---

## Final check against `slice.json`

- [ ] Every field in `readmodels[].fields[]` exists in the state or in `shape/1`.
- [ ] `query/1` names **every** event type that appears in the `mapping:` values.
- [ ] The `derived:` fields are computed, not stored.
- [ ] Every `specifications[]` has its `describe`.
- [ ] There's a test for the empty initial state.
- [ ] Reads go through `MyApp.Reader.read/2`, not `Fact.read/2`.
- [ ] If the slice has `screens`, you have **not** written an interface: you have
      written the **screen brief** at `docs/screens/<slice>.md`, as
      `.build-kit/CLAUDE.md` requires, and noted it in `progress.txt`.
