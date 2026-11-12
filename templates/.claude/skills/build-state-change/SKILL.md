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

## Step 2 — The command

**File:** `lib/my_app/slices/<slice>/<slice>.ex`

```elixir
defmodule MyApp.Slices.<Slice>.<Slice> do
  use MyApp.Command

  embedded_schema do
    field :<entity>_id, :string
    field :field_a, :string
    field :field_b, :integer
  end
end
```

That's the whole file. `use MyApp.Command` (`lib/my_app/command.ex`) gives it
`new/2` and `changeset/2`: **every field is required** unless named in
`optional:` — `use MyApp.Command, optional: [:field_b]` for the fields with
`optional: true` on the board.

**The fields are the ones in `commands[].fields[]` in `snake_case`**, plus the
generated ones from step 3. Types:

| `slice.json` | `field` |
|---|---|
| `type: "String"` / `"UUID"` | `:string` |
| `type: "Int"` | `:integer` |
| `type: "Double"` / `"Decimal"` | `:float` / `:decimal` |
| `type: "Boolean"` | `:boolean` |
| `type: "Date"` | `:date` |
| `type: "DateTime"` | `:string` (ISO 8601, as the events carry it) |
| `type: "Custom"` | `:map` |
| `cardinality: "List"` | `{:array, <type>}` |
| `optional: true` | in `optional:` |

A closed list or a format **stated in the field's `description`** goes in an
override of `changeset/2` that calls `super/2` and adds `validate_inclusion/3`
or `validate_format/3`. Nothing else: no shape rule the schema or the
description doesn't state, and never in `core.ex`.

**No messages in the command.** A missing field comes back as an error key
(`validation: :required`); the screen turns it into words.

---

## Step 3 — Generated fields (a rule `slice.json` doesn't state)

`slice.json` marks fields `generated: true` or
`mapping: "derived:append instant"`. **Don't generate them in `Core`.**

`Core` is pure: a `DateTime.utc_now()` or an `Ecto.UUID.generate()` inside `execute/2` makes
the decision impossible to test without a clock and without seeding randomness.

> **Identifiers and timestamps are generated in `context.ex` and travel on the
> command struct**, even though `slice.json` doesn't list them among the
> command's fields.

This is the **only** authorised deviation from "if it isn't in `slice.json`, it
isn't in the code".

- Identifiers → `Ecto.UUID.generate()`
- Timestamps → `DateTime.utc_now() |> DateTime.to_iso8601()`

---

## Step 4 — The event struct and its tags

**File:** `lib/my_app/slices/<slice>/<event>.ex`, in `snake_case`.

```elixir
defmodule MyApp.Slices.<Slice>.<Event> do
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

**The event carries all of them; a query picks one.** An event says everything
it is about — `ComprobacionSolicitada` writes both `comprobacion:` and
`sesion:` — while a query names the single tag that scopes it: the write side
picks the one that is its consistency boundary, and each read model picks the
one its view is about. That's how two views fold the same events and answer
different questions.

The consequence worth remembering: **a query can only scope by a tag its events
actually carry.** Scope by one nothing writes and the query finds nothing, in
silence.

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
    {:ok, [%<Event>{...}]}
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

### Only domain rules here (a rule `slice.json` doesn't state)

`execute/2` holds the rules the board's `SPEC_ERROR` scenarios state — business
rules, with or without history. Shape (presence, type, format, closed lists)
was checked by the command's changeset before `Decide` read anything; see rule 3
of `.build-kit/CLAUDE.md`.

Error reasons are **domain atoms** (`:geometry_outside_country`,
`:plot_already_assigned`), not strings: the screen translates them.

**Exactly the board's, nothing defensive:**

- One error atom per `SPEC_ERROR`, with the board's code. No extra atom for a
  case another rule already covers (an unknown type is also "not a type this
  slice accepts").
- No fallbacks for values the command or an earlier rule guarantees
  (`x || %{}`, `x || "LOW"`). If it can't be nil, don't handle nil.
- An event field whose `mapping` is a command field copies the command field.
  Don't re-derive it.
- Helpers are `defp`. No public list of rejection reasons, no optional
  arguments nobody passes.

### Thresholds get justified

If you need a constant `slice.json` doesn't give you, write in a comment **where
it comes from and in what units**. An unjustified threshold is an invented
business rule.

---

## Step 6 — `context.ex`

**File:** `lib/my_app/slices/<slice>/context.ex`

```elixir
defmodule MyApp.Slices.<Slice>.Context do
  alias MyApp.Slices.<Slice>.{<Command>, Core}

  require Logger

  def <verb>(params) do
    with {:ok, cmd} <-
           <Command>.new(params, %{
             <entity>_id: Ecto.UUID.generate(),
             <timestamp>: DateTime.utc_now() |> DateTime.to_iso8601()
           }),
         {:ok, _events} <- write(cmd) do
      {:ok, cmd.<entity>_id}
    end
  end

  defp write(cmd) do
    MyApp.Decide.execute(MyApp.Application.fact_db(), Core, cmd)
  rescue
    e in RuntimeError ->
      Logger.error("could not write: #{Exception.message(e)}")
      {:error, :store_unavailable}
  end
end
```

**`params` go straight into `new/2`.** `cast/3` already keeps only the
schema's fields and treats `""` and `"   "` as missing, so no `params/1` that
re-picks fields and no `clean/1` that trims. The generated values go inline as
the second argument. No `change/1` wrapper either: the form validates against
`<Command>.changeset/1` itself.

Shape first: an ill-formed command never reads the store. And `write/1`
rescues because `Application.fact_db/0` **raises** if the store isn't up, and
this gets called from LiveView handlers: an exception there kills the visitor's
session and takes with it whatever they had just entered.

Return `{:ok, <identifier>}`, not `{:ok, events}`: the identifier is what the
layer above needs to subscribe to the result and to show the reference.

The two ways it says no, and what the user sees:

- `{:error, %Ecto.Changeset{}}` — the shape is wrong. The form renders it with
  `to_form/1`, under each field; the words come from `translate_error/1`
  (Gettext), never from the command.
- `{:error, atom}` — a domain rule refused it (a board `SPEC_ERROR`). The screen
  translates the atom.

A processor builds commands from facts, so a changeset error there is a bug,
not an answer: log it and let the task fail.

---

### The one seam the view is allowed to reach through

`context.ex` is the slice's public surface, and a LiveView or controller should
go through it. There is exactly one exception worth allowing, and it needs
stating because otherwise it gets copied without its conditions:

> A view may call a **pure predicate on `Core`** to answer "would this command
> be accepted?" without sending it.

For **shape**, the view doesn't need this seam: it validates against
`<Command>.changeset/1` on `phx-change`, the usual Phoenix way. The seam is for a
**domain** check that needs no history.

The case that earns it: a form or a map that has to enable or disable its submit
button as the user types. Going through `Context` means a round trip and a
written event for something the user hasn't committed to yet. Calling
`Core.valid_<thing>?/1` costs nothing and stays honest, because `Core` is pure —
no store, no clock, no identifiers.

**Three conditions, all of them:**

- The function is **pure** — the same purity `Core` has everywhere else. The
  moment a `Core` function touches the store or the clock, this stops being
  safe and the view has to go through `Context`.
- It **answers, it doesn't act.** A predicate or a `:ok | {:error, reason}`. If
  the view wants something to happen, that's `Context`.
- The **same check still runs inside `execute/2`.** This is a convenience for
  the interface, never the enforcement. Validation that only lives in the view
  is validation an API call walks straight past.

Everything else — writing, reading a projection, generating an id or an
instant — goes through `Context`. And the direction never reverses: nothing
under `lib/<app>/` may name a module from `lib/<app>_web/`. The one legitimate
exception is `application.ex`, which starts the Endpoint because it is the
composition root and knows about everything it supervises.

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
- A `SPEC_ERROR` scenario is a domain rule: `assert {:error, :reason} = Core.execute(...)`.
- **Never compare `Map.keys/1` against a list** — the order isn't guaranteed and
  the assertion fails intermittently. Use `MapSet`.
- **A fixture must never invent the shape of its own input.** Board examples are
  the input here, so following the rule above already satisfies this. But the
  moment a test feeds something that exists outside the repo — a data file, an
  API response, a deployed artefact — the fixture has to be derived from it and
  guarded against drift, or the test only proves the code agrees with itself.
  `/build-automation`, step 2, has the guard.

### `command_test.exs` — the shape

**File:** `test/my_app/slices/<slice>/command_test.exs`. Pure, like the core test.

- One test for the board's example: `{:ok, %<Command>{}} = <Command>.new(params)`
  with the `when` fields of a specification.
- One test per required field: without it, `{:error, changeset}` with the
  error on that field (`errors_on`-style: `changeset.errors[:field]`).
- One per closed list or format the description states.
- If the board still carries a shape `SPEC_ERROR` scenario, its `describe` goes
  here, with its literal title, not in `core_test.exs`.

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

- [ ] Every field in `commands[].fields[]` is in the command's `embedded_schema`.
- [ ] The command is `use MyApp.Command` + `embedded_schema`; only the
      `optional: true` fields in `optional:`; no shape rule the schema or the
      description doesn't state; no messages.
- [ ] `context.ex` builds the command with `new/2` before calling `Decide`.
- [ ] Every field in `events[].fields[]` is in the event struct.
- [ ] No invented fields — except the generated ones from step 3.
- [ ] No `@moduledoc`, no `@doc`, no comment restating the board (`.build-kit/CLAUDE.md`, "No prose in slices").
- [ ] Every `idAttribute: true` produces its tag.
- [ ] Every `specifications[]` has its `describe` in the test.
- [ ] `Core` has no side effects: no `utc_now`, no `Ecto.UUID`, no `Req`, no `Fact`.
- [ ] `Core` holds no shape checks: only the board's domain rules, one atom
      per `SPEC_ERROR`, no defensive fallbacks.
- [ ] `context.ex` passes `params` straight to `new/2`: no field re-picking, no
      cleaning, generated values inline.
- [ ] `apply_event/2` has a final clause ignoring what isn't its own.
- [ ] If the slice has `screens`, you have **not** written an interface: you have
      written the **screen brief** at `docs/screens/<slice>.md`, as
      `.build-kit/CLAUDE.md` requires, and noted it in `progress.txt`. Include
      the **error atoms** `Core` returns: the screen translates them and can't
      guess them.
