# Build kit: Elixir · Phoenix · FACT

Turns slices from an [eventmodelers.ai](https://eventmodelers.ai) board into
Elixir code, using **event sourcing on [`fact`](https://hex.pm/packages/fact)**
— files on disk, no database — and vertical slice architecture.

```
npx @eventmodelers/cli init --stack elixir-fact \
  --git https://github.com/ortegacmanuel/eventmodelers-elixir-fact-kit
```

## What it installs

| | |
|---|---|
| `.claude/skills/build-*` | four skills: state-change, state-view, automation, webhook |
| `.claude/skills/build-*/references/` | the deep material: finding tags, materialised projections |
| `.build-kit/CLAUDE.md` | the blueprint — "how we build things here" |
| `.build-kit/lib/*.md` | the ralph loop prompts |
| project root | a real Phoenix app: endpoint, router, layouts, assets, supervision tree — compiles and its tests pass as installed |
| `lib/my_app/` | the framework: `decide`, `reader`, `state_change`, `state_view`, `command`, `event` |
| `test/support/scenario.ex` | `MyApp.Scenario`: the board's scenarios as `given \|> decide/read \|> expect` |
| `test/my_app/` | the guards: slice isolation, scenario tests only, the read path agrees with FACT, every automation's queue exposes `pending/0`, no Ecto in the domain |
| `docs/screens/` | a worked example of a screen brief |

The shared skills — `connect`, `learn-eventmodelers-api`, `update-slice-status`,
`request-feedback` — come from the CLI itself.

**About 560 lines of framework Elixir and 1,750 lines of instructions.** The Elixir is what
runs; the instructions are what makes an agent produce the same shape every time.

## Phoenix + fact + what, exactly

`fact` is an event store. It gives you two things: **append** and **read**, plus
indices by type and by tag. It does *not* tell you how a command decides, what
happens when two writes race, how a read model gets built, how a domain struct
becomes storable, or where any of it lives.

Those 560 lines are that gap:

| module | what it solves |
|---|---|
| `decide.ex` | **the whole write path**: read → fold → decide → append. Optimistic concurrency (DCB), retry on conflict, and a wait until the write is visible to a subsequent read |
| `reader.ex` | **the read path**: uses `fact`'s indices instead of scanning the ledger. Measured: 235 ms → 0.07 ms over 20,000 events |
| `state_change.ex` | the contract for a write slice: `query`, `append_condition`, `initial_state`, `apply_event`, `execute`, and optionally `next_query` to follow a reference read in the first pass |
| `state_view.ex` | the contract for a read slice: `query`, `initial_state`, `apply_event`, and optionally `next_query` and `project` (shape the folded state for the screen) |
| `event.ex` | protocol: domain struct → `fact` map (`type`, `data`, **`tags`**), declared with `@derive` on the struct |
| `command.ex` | `use MyApp.Command`: an `embedded_schema` with `new/2` and `changeset/2`, required fields unless the board says optional |

**What you don't get, and that's half the point:** no database, no migrations,
no Ecto schemas, no `Repo`, no projection tables. **Read models are folded on
the fly** every time you ask. A read slice is two files and zero SQL.

Without the framework each slice would call `Fact.append` and `Fact.read` its own
way. With it there is *one* write path and *one* read path, so every slice looks
the same — which is the precondition for an agent generating them unattended.

## Before installing

**Nothing.** Install into an empty directory and you get a Phoenix project that
compiles and whose `mix precommit` passes: endpoint, router, layouts, assets
with esbuild and Tailwind, and the FACT framework already in the supervision
tree. One `sed` to rename the namespace and you're building slices.

**Already have a project? Don't run `init`.** It copies `templates/root/` over
your files before it prompts about anything — the one question it asks is about
`.build-kit/`, by which point `mix.exs` and `config/` are already gone. Install
into an empty directory and copy across the four things `INSTALL.md` lists.

**And `--hooks` now installs something.** `.githooks/pre-commit` runs the slice
commit-scope guard: a commit that touches two slices, or that changes the
framework while building a slice, is refused. `--no-verify` gets past it, on
purpose.

**On OTP 27, assets need a hand.** GitHub's release CDN serves a certificate OTP
rejects with `key_usage_mismatch`, so `mix tailwind.install` fails —
`./scripts/ensure-asset-binaries.sh` pulls the same binaries with `curl`. It
surfaces as a runtime error on the first page load, with the server already up,
so it doesn't read like a build problem.

**Keep the path short.** FACT takes its lock through a Unix domain socket, and
those cap at ~104 characters. A deep project path fails at boot with a
`Fact.Database … :einval` that says nothing about the real cause.

`--no-ecto` on purpose: the domain has no database. If you need Ecto for
something else — forms via `phoenix_ecto`, a throwaway mirror of an external
system — add it later, but **keep it out of the domain**.

## After installing

One step: rename the namespace. It ships as `MyApp` / `my_app` because the CLI
copies files without templating, so it's a one-line `sed` — `INSTALL.md`, which
the kit drops in your project root, has it ready.

```bash
mix setup && mix precommit
```

## The four slice shapes

| `slice.json` has | skill | files |
|---|---|---|
| `commands` / `events` | `build-state-change` | command, event, `core`, `context` |
| `readmodels` / `queries` | `build-state-view` | `core`, `context` |
| non-empty `processors` | `build-automation` | those four + `processor` |
| an inbound external event | `build-webhook` | those four + controller and plug |

**An automation reads a TODO list, it doesn't react to an event.** That is
Event Modeling's automation pattern, and what the board draws: events open and
close items on a read model, the `READMODEL → AUTOMATION` edge feeds the
processor, the processor issues the command. Here the processor polls that read
model — its own state-view slice — through `pending/0`. Most other build kits
subscribe the processor to a trigger event instead, and rebuild whatever list
they need inside it.

## What this kit does NOT do

**Screens.** `slice.json` carries a screen as metadata and prose — **not as a
design**. The rendered HTML from the board never travels in the payload.

When a slice has `screens`, the agent builds the domain, writes a **screen
brief** at `docs/screens/<slice>.md`, and stops.

That brief is the `ui-prompt.md` the loop anticipates in step 12 and that no
shipped stack fills in. Its most useful section is **"What the domain does NOT
give you"** — it's what stops whoever builds the view from inventing fields or
asking the domain for things it shouldn't own. There's a worked example in
`docs/screens/`.

## Known limitation: the append condition can miss a very recent write

`decide.ex` appends with a DCB condition: *fail if anything matching my query
was written after the position I read*. FACT checks that condition against its
**index files**, and those are updated asynchronously, a few milliseconds after
the write is committed. If a second conflicting write arrives inside that
window, the check doesn't see the first one and both are accepted — silently.

- **When it bites:** two writes guarded by the same rule (same tags) within
  roughly a millisecond of each other. A person double-clicking is not enough —
  LiveView disables the button during the round trip — but two processes, or a
  processor and a person at once, can be.
- **What you'd see:** an event a rule should have rejected, e.g. a duplicate
  code. No error is raised.
- **What the kit already does:** retries on a detected conflict, and waits after
  each write until it is visible to the next read. That narrows the window but
  does not close it: the wait goes through one index, not all of them.
- **Status:** affects FACT 0.2.x and 0.4.x alike; it is a property of the store,
  not of this kit. A fix (the writer waiting for every indexer to reach its
  position before checking) is planned as a contribution to FACT, along with
  support for other stores. Until then, if a rule must never be broken under
  concurrent writes, serialize those writes yourself.

## Three rules `slice.json` doesn't tell you

They live in `.build-kit/CLAUDE.md` and they are the reason this kit exists. You
can't derive them by reading other build kits — they came from building a slice
by hand and hitting them:

1. **Tags come from `idAttribute: true`.** `slice.json` ships `tags: []` on every
   element: they aren't empty, they're **underived**. And tags are the query keys
   for the entire system — a made-up tag doesn't fail, it silently stops finding
   events downstream. The scenario tests catch it: `MyApp.Scenario` stores the
   `given` with the production tags and reads it back through the slice's own
   query, so a query that misses an event fails the test and names the event.
2. **Generated fields travel on the command.** A `derived:append instant` looks
   like it's produced at write time; doing that inside `Core` breaks purity and
   leaves the decision impossible to test without a clock.
3. **Validation doesn't get split** between `Core` and `Context`. The board's
   `SPEC_ERROR` scenarios run through `MyApp.Scenario` against the `Core`, which
   never goes through `Context`.

## Loop quirks worth knowing

Not bugs in this kit — behaviour of the ralph loop that will bite you:

- **The `slice.json` the loop writes is a stub.** `fetchAndPersistSlices` uses
  the *summary* endpoint: six fields, ~230 bytes, no `fields`, no `events`, no
  `specifications`. Step 0 of `CLAUDE.md` makes checking for it mandatory, and
  the fix is the CLI's own `fetch --context <ctx>`, which writes the full
  definition to the same place. Easy to miss, because the file exists and
  parses — it's just empty of everything that matters. And the stub also has no
  board comments, which all four skills read as hints.
- **An idle loop may not notice a slice you mark `Planned`** if the realtime
  event doesn't arrive. Refreshing the local index unblocks it.
- **Planned slices are built in no particular order.** The loop takes the
  first Planned slice in the order the server returns them, which is neither
  the board's columns nor the dependencies, and changes over time. An
  automation can come before its TODO queue: it is built against
  `<Queue>.Context.pending/0`, logs a warning on every poll until the queue is
  built, and `automation_queue_test.exs` checks the two agree once both are.
- **An automation's external system must be written on the board.** Name it in
  the AUTOMATION's description (a real API, or a fake that only logs). Without
  it, the processor records the fact and sends nothing.
- **The canonical folder name keeps accents and `·`**: it's `title` with spaces
  removed, lowercased. Normalising to ASCII creates a parallel folder the loop
  never looks at.

## Provenance

Derived from building the first chapter of [NAMU](https://namupartner.com) — EUDR
traceability for Venezuelan cocoa and coffee — slice by slice.

The kit was validated by using it: five real defects surfaced from running it,
none from reading it. All five are closed, in the blueprint or in the skills.

## License

MIT — see [LICENSE](LICENSE).

The loop prompts in `templates/build-kit/lib/` are adapted from the node and
supabase templates of [@eventmodelers/cli](https://www.npmjs.com/package/@eventmodelers/cli)
(MIT, © Martin Dilger).
