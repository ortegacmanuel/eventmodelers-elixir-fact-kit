# Blueprint: Elixir + Phoenix + FACT (event sourcing, no database)

This is "how we build things here". Not a style guide: it's the contract that
lets an agent implement a slice without anyone having to review where each file
goes or what each thing is called.

Domain events live in `lib/my_app/slices/<slice>/`, one per file. The framework
is in `lib/my_app/` — read it before your first slice: `decide.ex`, `reader.ex`,
`state_change.ex`, `state_view.ex`, `event.ex`, `command.ex`.

## File constraints

- **Strict path:** work inside `lib/my_app/slices/<slice>/*` and
  `test/my_app/slices/<slice>/*`. Nothing else, unless the skill you're running
  says so explicitly.
- **One slice, one folder.** Never files from two slices mixed together.
- **Don't touch `lib/my_app/` (the framework)** or `lib/my_app_web/` unless
  asked. This kit doesn't build screens — see below.

## Standards

- **Language:** Elixir. **Framework:** Phoenix 1.8+. **Store:** `fact` 0.2.0,
  files, no database.
- **Domain names follow the board.** If the model is written in another
  language, keep it: slice titles, event names and field names come from
  `slice.json` and are the shared vocabulary with the people who modelled it.
  The framework modules keep their English names.
- **Ecto for commands, never for storage.** A command is an `embedded_schema`
  validated by an `Ecto.Changeset` (rule 3 below). No `ecto_sql`, no `Repo`, no
  `schema "..."`, no migrations: the store is `fact` and read models are
  folded. `core.ex`, events and views never touch Ecto. Identifiers:
  `Ecto.UUID.generate/0`, called in `context.ex`.
- **No prose in slices.** The board is the documentation: everyone reads the
  model, and the code is generated from it. No `@moduledoc`, no `@doc`, no
  comment that restates a field, a rule or a scenario. A comment is one line,
  and only for what the board doesn't carry: an assumption you made, where a
  constant comes from, a quirk of an external system.
- **HTTP:** `Req`. Never `httpoison`, `tesla` or `httpc`.
- **Never nest modules in one file**: it causes cyclic dependency errors.

## Architecture rules

- **All invariants live in `core.ex`, which is pure.** No side effects, no
  network, no store access. `execute/2` returns `{:ok, [events]}` or
  `{:error, atom}`.
- **`core.ex` is the contract and nothing else:** `query`, `initial_state`,
  `apply_event`, `execute` (and `append_condition` when overridden). No other
  `def` or `defp`; `core_contract_test.exs` enforces it.
- **Every write goes through `MyApp.Decide.execute/4`.** Never call
  `Fact.append` directly: `Decide` is what retries on concurrency conflicts and
  what waits until the write is visible.
- **Every read goes through `MyApp.Reader.read/2`**, not `Fact.read` directly:
  it picks an index instead of scanning the ledger.
- **Slices don't couple.** They share only the event type *strings*. Never
  shared structs: `apply_event/2` matches raw maps
  (`%{"event_type" => ..., "event_data" => ...}`).
- **Pure `append` by default.** Re-evaluating must be free; the last event in
  log order wins.

## Which tests get written

- **What pins down the board, and nothing else**, under
  `test/my_app/slices/<slice>/`:
  - `core_test.exs`: the board's scenarios — `Core.execute/2` of a write slice
    (its `SPEC_ERROR`s are domain rules), `apply_event/2` of a read slice. One
    `describe` per scenario, with its title from the board.
  - `command_test.exs`: the command's shape, from its field schema (rule 3).
- **Never tests of screens, controllers or plugs** (`test/my_app_web/`): they
  aren't written and aren't rebuilt.
- Anything that is not one of those — the mapping of an external response, a
  TODO queue, an adapter — carries `@moduletag :extra`. The default suite
  excludes it; run it with `mix test --include extra`.
- The test `fact` store is emptied at the start of every `mix test`
  (`fact.reset`). The whole suite takes seconds: there is no reason to skip it.

## Building a slice

**Always use the matching skill. Never implement a slice by hand.**
**Every field, event name, command name and business rule comes EXCLUSIVELY from
`slice.json`.** Don't invent anything that isn't there.

0. **Check the `slice.json` is complete before anything else.** The loop
   populates `.slices/` from the **summary** endpoint, which returns six fields
   (`id`, `title`, `status`, `sliceType`, `contextId`, `contextName`) and
   **no `fields`, no `events`, no `specifications`**. A ~230-byte file is a stub
   and you cannot build from it. It's easy to miss: the file exists and parses,
   it's just empty of everything that matters.

   If it is one, refresh with the CLI:

   ```
   npx @eventmodelers/cli fetch --context <context>
   ```

   It writes the full definition into the same `.build-kit/.slices/` the loop
   uses, with the same folder naming, so it leaves no duplicates. It also brings
   two things the stub hasn't got and the skills need: **the board comments on
   every element**, which they read as hints and resolve afterwards, and a
   `config.json` with the whole context.

1. Read `.build-kit/.slices/<context>/<slice>/slice.json`.
2. Work out the shape and call the skill:
   - `sliceType == "TRANSLATION"` → read `description` and `notes`; default to
     `/build-automation`. In this stack translation happens **inline** inside
     the processor, never as a separate slice.
   - **an inbound external event** (the outside system starts it: a confirmation
     that arrives, a result another service returns later) → `/build-webhook`.
     The `description` says so; if you're torn between this and an automation,
     the question is **who starts**.
   - non-empty `processors` → `/build-automation`
   - non-empty `readmodels` or `queries` → `/build-state-view`
   - default (has `commands` / `events`) → `/build-state-change`
3. Follow the whole skill. Don't deviate.
4. **Verify against `slice.json`**: every command field, every event field and
   every specification must appear in the code. If it isn't in `slice.json` it
   must not be in the code — with **one exception**, generated fields, below.
5. `mix precommit` (compiles with `--warnings-as-errors`, formats, runs tests).
   Then the slice's own tests.
6. If it passes: `git commit -m "feat: <Slice Name>"` and set status `Done`.

## Three rules `slice.json` doesn't tell you

They came from building the first slice **by hand**, before this kit existed.
Without them an agent produces code that compiles and is wrong. The examples are
from that slice; the rules are general.

### 1. Tags come from `idAttribute: true` and `tag: true`

`slice.json` ships `tags: []` on every element. **Tags aren't empty, they're
underived.** The rule is mechanical:

> Every event field — or subfield — with `idAttribute: true` or `tag: true`
> produces a tag `<name without the Id suffix, in snake_case>:<value>`. A tag
> that doesn't come from the board is invented.

**The event carries all of them; a query picks one.** An event says everything
it is about — `ComprobacionSolicitada` writes both `comprobacion:` and
`sesion:` — while a query names the single tag that scopes it: the write side
picks the one that is its consistency boundary, and each read model picks the
one its view is about. That's how two views fold the same events and answer
different questions.

The consequence worth remembering: **a query can only scope by a tag its events
actually carry.** Scope by one nothing writes and the query finds nothing, in
silence.

`checkId` and `sessionId` → `["check:#{e.check_id}", "session:#{e.session_id}"]`.

This matters more than anything else here: **tags are the query keys of the
whole system**. `query/1`, the read models and the TODO queues all ask by them.
A made-up tag doesn't fail — it silently stops finding events downstream.

If an event has no `idAttribute: true` and no `tag: true` at all, **stop and invoke
`request-feedback`**: an event with no tags can't be queried.

### 2. Generated fields travel on the command

`slice.json` marks fields `generated: true` or with `mapping: "derived:..."`. A
`derived:append instant` on the event looks like it's produced at write time —
**don't do that in `Core`**. `Core` is pure, and a `DateTime.utc_now()` inside
`execute/2` makes the decision impossible to test without a clock.

> Identifiers and timestamps are generated in `context.ex` and travel on the
> command struct, even though `slice.json` doesn't list them among the command's
> fields.

This is the only authorised deviation from "if it isn't in `slice.json`, it
isn't in the code".

### 3. Shape is the command's job; `core.ex` holds the domain

The modeling rule this kit builds against, from Nebulit's modeling kit
(`eventmodeling-elaborating-scenarios`, 2026-10-07):

> **Scenarios specify business rules, not technical guarantees.** Every rejection must name a rule a domain expert would recognise and could argue about ("a closed day takes no new todos"). Do not write scenarios for: duplicate or colliding ids, retries/idempotency of the same request, missing or malformed required fields, type/format checks, or infrastructure failures — the implementation handles those and they say nothing about the domain. Rules the brief states explicitly (e.g. "adding on a closed day is rejected") are the core of the coverage and must all be present.

So the board's `SPEC_ERROR` scenarios are **domain rules**, and the shape of a
command is not on the board as scenarios — it is in the command's
`fields[]`. The build splits along the same line:

- **Shape → the command.** A command is `use MyApp.Command` plus an
  `embedded_schema` with the board's fields: every field is required unless
  it's `optional: true` on the board. `<Command>.new/2` returns `{:ok, cmd}` or
  `{:error, %Ecto.Changeset{}}`. A closed list or a format stated in the
  field's `description` → `validate_inclusion` / `validate_format`. Nothing
  else, and no messages: the error is a key, the screen picks the words.
- **Domain → `core.ex`.** `execute/2` assumes a well-formed command and holds
  only the rules a domain expert would state: the `SPEC_ERROR` scenarios. A
  rule needing no history is still domain if it relates fields to each other
  or to a reference the business or a regulation sets ("the EORI prefix must be
  the declared country's").
- **`context.ex` builds the command before `Decide`.** An ill-formed command
  never reads the store. The form shows the changeset's errors on each field
  (`to_form/1`); domain atoms are translated by the screen, as before.
- **Tie-break:** if the rule's wording would change when the screen or the API
  changed, it is shape.
- **An older board may still carry shape scenarios.** Implement them in the
  changeset and test them in `command_test.exs` under the scenario's literal
  title — not in `Core`.

## What this kit does NOT do: screens

`slice.json` carries the screen as metadata — `title`, `fields`, `dependencies`
and the prose in `description` — but **not as a design**. Whatever HTML lives on
the board never travels in the payload. LiveViews are written by hand.

If the slice has `screens`: **build the domain, write the screen brief, stop.**
Don't invent an interface.

### The screen brief

This is step 12's `ui-prompt.md`. Here it's `docs/screens/<slice-in-kebab>.md`,
it's **version controlled** — unlike `.build-kit/`, which is regenerated — and
it's the contract between the domain and whoever builds the view.

**Worked example:** `docs/screens/EXAMPLE-check-a-plot.md`, which the kit leaves
in the project. It's a real brief from another system, so you can see how much
detail is worth writing. Delete it once you have your own.

It is not a design or a proposal. It's **what's available and what isn't**, so
whoever builds the view doesn't have to read the whole slice or make things up.

> **Link the mockup, if the board has one.** A screen is often designed on the
> board before it's built — the modeling kit's `html-screen` skill renders real
> HTML and CSS onto an `HTML_SCREEN` node. That markup does **not** travel in
> `slice.json`: `screens[]` carries only `title`, `description` and `fields`,
> and `screenImages` is usually empty. The pages live on the node, behind
> `mcp__eventmodelers__get_node` with the screen's id.
>
> So put the node id in the brief and say the mockup is there. Otherwise the
> design and the build never meet: whoever builds the view has the contract and
> not the picture, and reinvents a layout somebody already decided.
>
> Say plainly whether one exists. "No mockup on the board" is useful; silence
> reads as "there isn't one" and is wrong half the time.

Template:

```markdown
# Screen: <the screen's title on the board>

Slice `<title>` · node `<screen node id>` · written by the loop on <date>.

<Mockup: "designed on the board — `get_node` with the id above", or
"no mockup on the board".>

## How it's entered

<The Context's public function, with its signature and what it returns. Verbatim.>

## What it returns

| field | type | | what it is |
|---|---|---|---|
| `field` | `String` | | <from the board's description, not invented> |

<Mark as optional the ones that may not be there yet, and say **why** — almost
always "the event that carries it hasn't arrived".>

## What it sends back

<Only if the slice has a command. The function, its arguments, and **the error
atoms it can return**, which the screen has to translate into messages.>

## States to render

<Empty, partial, complete, error. A read model with no events must be
renderable: say what shows then.>

## What the board says about this screen

<The screen node's `description`, quoted. It's the design intent, and the only
thing that survives from the board, because the HTML doesn't travel.>

## What the domain does NOT give you

<The most important section. Fields the screen might want that don't exist, and
whether that's deliberate. Stops whoever builds the view from inventing them, or
from asking the domain for them without cause.>
```

Rule while writing it: **everything comes from `slice.json` and from the code
you just wrote.** If you don't know what a field means, quote the board's
`description` instead of paraphrasing. Don't propose layout, copy or colours.

### When the screen gets built

Whoever builds the LiveView from the brief follows the same idea as the domain:
the screen holds presentation only.

- **One form, from the command.** `to_form(<Command>.changeset(params, derived))`
  in `mount` and on every `phx-change`, with `action: :validate`. The values the
  screen derives (ids from the URL, the session's account, a field assembled
  from several inputs) go as the second argument; the user's inputs stay the
  form's params. No parallel map of values, no form that starts as `nil`.
- **Errors per field, with `used_input?/1`**, the way Phoenix's `<.input>` shows
  them: an error appears once the field was touched or the form submitted. The
  words come from `translate_error/1` (Gettext).
- **Uploads:** `allow_upload/3` rejects size and type; show `upload_errors/2`
  under the input as soon as a file is picked. Check the form's shape before
  consuming the upload, so a missing field doesn't cost the user their file.
- **No domain or catalogue knowledge in the screen.** A list of types, a rule,
  a threshold: read it from where the domain keeps it. The domain's error
  atoms are translated into words, nothing more.
- **No prose:** no `@moduledoc` or `@doc`, a comment only for what the board
  doesn't carry.

## Slice shape

```
lib/my_app/slices/<slice>/
├── <slice>.ex         # command struct         (write slices only)
├── <event>.ex         # @derive {MyApp.Event, type:, tags:} + defstruct
├── core.ex            # use MyApp.StateChange — all invariants, pure
├── context.ex         # public API: generate, build, Decide.execute
└── processor.ex       # automations only: GenServer polling the TODO queue

test/my_app/slices/<slice>/
└── core_test.exs      # the board's specifications, against the pure Core
```

A read slice is two files: `core.ex` and `context.ex`.

**Once you have a slice built, read it before the next one.** Existing code
beats these templates: if they diverge, the template is stale.

## Before you start

Read `.build-kit/AGENTS.md` if it exists, to load what earlier iterations
learned. And when you start a slice, invoke `update-slice-status` with
`InProgress` before anything else.

## If something is ambiguous

If `slice.json` is genuinely ambiguous, contradictory, or missing a decision you
need — **don't guess and don't build anyway**. Invoke `request-feedback` with
the specific question: it posts a comment on the slice and marks it `Blocked`.
Then stop.

This is an escape hatch, not a routine step: read the whole `slice.json` and the
whole skill first. Most slices are fully specified.
