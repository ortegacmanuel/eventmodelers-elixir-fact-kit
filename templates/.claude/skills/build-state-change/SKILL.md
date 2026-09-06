---
name: build-state-change
description: Implements a write slice (a command validated against replayed events, new events emitted) in Elixir with the FACT event store, from a slice.json
---

# Build a write slice

> Before anything else, read the definition at
> `.build-kit/.slices/{Context}/{slice}/slice.json`. That file is the **source of
> truth** for every field, event and piece of metadata. Never invent fields that
> aren't there.

> And read `.build-kit/CLAUDE.md`. It carries three rules `slice.json` doesn't
> state, and all three show up below — without them the code compiles and is
> wrong.

---

## What a write slice is

A command that decides, against history, whether to emit events. In this stack:

```
Context.function(...)  →  Decide.execute(db, Core, cmd)
                              1. Reader.read(db, Core.query(cmd))     → events
                              2. Enum.reduce(…, Core.apply_event/2)   → state
                              3. Core.execute(cmd, state)             → {:ok, [ev]} | {:error, m}
                              4. FactEvent.to_fact/1                  → maps
                              5. Fact.append(db, …, {append_condition, pos})
                              6. wait until the write is visible
```

`Core` is **pure**. `Decide` owns the side effects. `Context` is the only public
API.

---

## Step 1 — Read the `slice.json`

Pull out:

- **`title`** — the slice name. Names the folder, in `snake_case`.
- **`context`** — the bounded context.
- **`commands[]`** with their `fields[]`: `name`, `type`, `cardinality`,
  `idAttribute`, `generated`, `optional`, `mapping`.
- **`events[]`** — same, plus `dependencies` so you know who consumes them.
- **`specifications[]`** — the given/when/then scenarios **with example data**.
  They are the tests, almost literally.
- **Each element's `description`** — it carries the invariants written out in
  prose. It is the source of the business rules; read all of it.

> **Comments**: every element carries `comments: string[]`. Use them as hints.
> If a comment raises an **open decision** rather than a hint — "rate limiting
> still undecided", "own stream or the main registry?" — don't decide it
> yourself: invoke `request-feedback`. Resolve the ones you consume:
> `POST <BASE_URL>/api/org/<ORG_ID>/boards/<BOARD_ID>/nodes/<nodeId>/comments/<commentId>/resolve`.

---

## Step 2 — The command struct

**File:** `lib/my_app/slices/<slice>/<slice>.ex`

```elixir
defmodule MyApp.Slices.<Slice>.<Slice> do
  @moduledoc """
  Command: <what the actor wants to do, in one domain sentence>.

  <And why the fields are these. If there are generated fields, say here that
  they travel on the command even though the board doesn't list them — see
  below.>
  """

  defstruct [:field_a, :field_b]
end
```

**The fields are the ones in `commands[].fields[]` in `snake_case`**, plus the
generated ones from step 3.

---

## Step 3 — Generated fields (a rule `slice.json` doesn't state)

`slice.json` marks fields `generated: true` or
`mapping: "derived:append instant"`. **Don't generate them in `Core`.**

`Core` is pure: a `DateTime.utc_now()` or a `uuid4()` inside `execute/2` makes
the decision impossible to test without a clock and without seeding randomness.

> **Identifiers and timestamps are generated in `context.ex` and travel on the
> command struct**, even though `slice.json` doesn't list them among the
> command's fields.

This is the **only** authorised deviation from "if it isn't in `slice.json`, it
isn't in the code". Write it down in the command's `@moduledoc`, with the reason.

- Identifiers → `MyApp.Id.uuid4()`
- Timestamps → `DateTime.utc_now() |> DateTime.to_iso8601()`

---

## Step 4 — The event struct and its tags

**File:** `lib/my_app/slices/<slice>/<event>.ex`, in `snake_case`.

```elixir
defmodule MyApp.Slices.<Slice>.<Event> do
  @moduledoc """
  Event: <what happened, past tense, in domain language>.

  <What it does NOT imply. The board's description usually says, and it's usually
  the most valuable thing there.>
  """

  defstruct [:field_a, :field_b]

  defimpl MyApp.FactEvent do
    def to_fact(e) do
      %{
        type: "<Event>",
        data: Map.from_struct(e),
        tags: ["<entity>:#{e.<entity>_id}", "<other>:#{e.<other>_id}"]
      }
    end
  end
end
```

### The tags (a rule `slice.json` doesn't state)

`slice.json` ships `tags: []` on every element. **They aren't empty, they're
underived.**

> Every event field with `idAttribute: true` produces a tag
> `<name without the Id suffix, in snake_case>:<value>`.

`checkId` → `"check:#{e.check_id}"`. `sessionId` → `"session:#{e.session_id}"`.

**This matters more than anything else in this skill.** Tags are the query keys
of the whole system: `query/1`, the read models and the TODO queues all ask by
them. A made-up tag doesn't fail — it silently stops finding events downstream.

If an event has no `idAttribute: true` at all, **stop and invoke
`request-feedback`**: an event with no tags can't be queried.

> **When the rule runs out**, read `references/finding-tags.md`. It carries the
> question to put to the modeller, and the case a single id can't express — a
> decision that needs two histories at once, which DCB handles in one append
> where aggregate modelling would need a saga.

### The event type

`type:` is the event's `title` **verbatim**, PascalCase, no spaces. It's the
string other slices' `apply_event/2` match on, so don't embellish it.

---

## Step 5 — `core.ex`

**File:** `lib/my_app/slices/<slice>/core.ex`

```elixir
defmodule MyApp.Slices.<Slice>.Core do
  @moduledoc """
  <What it decides, and by what rules. If the board removed rules that seem
  obvious, say which and why: that's what stops them coming back.>
  """

  use MyApp.StateChange

  alias MyApp.Slices.<Slice>.{<Command>, <Event>}

  @impl true
  def query(%<Command>{} = cmd) do
    Fact.QueryItem.types(["<Event>"])
    |> Fact.QueryItem.tags(["<entity>:#{cmd.<entity>_id}"])
  end

  @impl true
  def initial_state, do: %{already_happened: false}

  @impl true
  def apply_event(state, %{"event_type" => "<Event>"}), do: %{state | already_happened: true}
  def apply_event(state, _), do: state

  @impl true
  def execute(_cmd, %{already_happened: true}), do: {:ok, []}

  def execute(%<Command>{} = cmd, _state) do
    with :ok <- validate(cmd) do
      {:ok, [%<Event>{...}]}
    end
  end
end
```

### What to read in `query/1`

**Only what the decision needs.** Not "every event for this entity": the minimum
set that answers the question `execute/2` asks.

If the only invariant is idempotency, `query/1` is the event type itself scoped
by its identifier — with a freshly generated id it folds nothing, and at the same
time it guards against a retry with the same id.

`append_condition/1` falls back to `query/1`, which is the safe default. Override
it only when concurrent events **cannot** invalidate the decision.

### All validation here (a rule `slice.json` doesn't state)

The usual rule sends invariants to `core.ex` and shape validation to
`context.ex`. With the board's specifications that doesn't work: the `SPEC_ERROR`
scenarios are tested in `core_test.exs`, which is pure and never goes through
`Context`.

> **All validation lives in `core.ex`**, shape checks included. Decoding JSON,
> checking ranges or counting elements is pure, so it fits. `context.ex` only
> cleans (`nil`, whitespace) and builds the command.

Error reasons are **domain atoms** (`:geometry_required`,
`:polygon_encloses_no_area`), not strings: the screen translates them.

### Thresholds get justified

If you need a constant `slice.json` doesn't give you, write in a comment **where
it comes from and in what units**. An unjustified threshold is an invented
business rule.

---

## Step 6 — `context.ex`

**File:** `lib/my_app/slices/<slice>/context.ex`

```elixir
defmodule MyApp.Slices.<Slice>.Context do
  @moduledoc "Public API of <the slice>."

  alias MyApp.Slices.<Slice>.{<Command>, Core}

  require Logger

  def <verb>(args...) do
    id = MyApp.Id.uuid4()

    cmd = %<Command>{
      <entity>_id: id,
      ...,
      <timestamp>: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case write(cmd) do
      {:ok, _events} -> {:ok, id}
      error -> error
    end
  end

  # `Application.fact_db/0` **raises** if the store isn't up, and this gets
  # called from LiveView handlers: an exception there kills the visitor's
  # session and takes with it whatever they had just entered.
  defp write(cmd) do
    MyApp.Decide.execute(MyApp.Application.fact_db(), Core, cmd)
  rescue
    e in RuntimeError ->
      Logger.error("could not write: #{Exception.message(e)}")
      {:error, :store_unavailable}
  end
end
```

Return `{:ok, <identifier>}`, not `{:ok, events}`: the identifier is what the
layer above needs to subscribe to the result and to show the reference.

---

## Step 7 — `core_test.exs`

**File:** `test/my_app/slices/<slice>/core_test.exs`

**One `describe` per specification in `slice.json`, with its literal title.** That
way you can see at a glance which board scenario each block covers.

```elixir
defmodule MyApp.Slices.<Slice>.CoreTest do
  use ExUnit.Case, async: true

  alias MyApp.Slices.<Slice>.{<Command>, <Event>, Core}

  defp given(events),
    do: Enum.reduce(events, Core.initial_state(), &Core.apply_event(&2, &1))

  defp fact_event(type, data \\ %{}),
    do: %{"event_type" => type, "event_data" => data}

  defp cmd(overrides \\ %{}), do: Map.merge(%<Command>{...}, overrides)

  describe "<the specification's literal title>" do
    test "<what it pins down>" do
      assert {:ok, [%<Event>{} = e]} = Core.execute(cmd(), given([]))
      assert e.field == "<the example from slice.json>"
    end
  end
end
```

Rules:

- **The pure `Core` only.** No store, no `Context`, no `ConnCase`.
- **The data comes from `specifications[].given/when/then[].fields[].example`**,
  literally. Don't invent values: the board's are usually measured.
- **Test `FactEvent.to_fact/1` too**: type, data and **the tags**. It's the only
  thing that pins down the rule from step 4.
- The `given` events are built as **string-keyed maps**, respecting the boundary
  that keeps slices independent.
- A `SPEC_ERROR` scenario is `assert {:error, :reason} = Core.execute(...)`.
- **Never compare `Map.keys/1` against a list** — the order isn't guaranteed and
  the assertion fails intermittently. Use `MapSet`.
- **A fixture must never invent the shape of its own input.** Board examples are
  the input here, so following the rule above already satisfies this. But the
  moment a test feeds something that exists outside the repo — a data file, an
  API response, a deployed artefact — the fixture has to be derived from it and
  guarded against drift, or the test only proves the code agrees with itself.
  `/build-automation`, step 2, has the guard.

### If a test fails, suspect the test

The board's examples are usually measured against real systems. Before changing
the code, check the assertion says what the scenario says.

---

## Step 8 — Quality gate

```
mix precommit                          # --warnings-as-errors, format, tests
mix test test/my_app/slices/<slice>/   # this slice only
```

Never commit with warnings.

---

## Final check against `slice.json`

- [ ] Every field in `commands[].fields[]` is in the command struct.
- [ ] Every field in `events[].fields[]` is in the event struct.
- [ ] No invented fields — except the generated ones from step 3, documented.
- [ ] Every `idAttribute: true` produces its tag.
- [ ] Every `specifications[]` has its `describe` in the test.
- [ ] `Core` has no side effects: no `utc_now`, no `uuid4`, no `Req`, no `Fact`.
- [ ] `apply_event/2` has a final clause ignoring what isn't its own.
- [ ] If the slice has `screens`, you have **not** written an interface: you have
      written the **screen brief** at `docs/screens/<slice>.md`, as
      `.build-kit/CLAUDE.md` requires, and noted it in `progress.txt`. Include
      the **error atoms** `Core` returns: the screen translates them and can't
      guess them.
