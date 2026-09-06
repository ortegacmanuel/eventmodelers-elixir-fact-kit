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
| `.build-kit/CLAUDE.md` | the blueprint — "how we build things here" |
| `.build-kit/lib/*.md` | the ralph loop prompts |
| project root | a real Phoenix app: endpoint, router, layouts, assets, supervision tree — compiles and its tests pass as installed |
| `lib/my_app/` | the framework: `decide`, `reader`, `state_change`, `state_view`, `fact_event`, `id` |
| `docs/screens/` | a worked example of a screen brief |

The shared skills — `connect`, `learn-eventmodelers-api`, `update-slice-status`,
`request-feedback` — come from the CLI itself.

**327 lines of Elixir and about 1,400 lines of instructions.** The Elixir is what
runs; the instructions are what makes an agent produce the same shape every time.

## Phoenix + fact + what, exactly

`fact` is an event store. It gives you two things: **append** and **read**, plus
indices by type and by tag. It does *not* tell you how a command decides, what
happens when two writes race, how a read model gets built, how a domain struct
becomes storable, or where any of it lives.

Those 327 lines are that gap:

| module | what it solves |
|---|---|
| `decide.ex` | **the whole write path**: read → fold → decide → append. Optimistic concurrency (DCB), retry on conflict, and a wait until the write is visible to a subsequent read |
| `reader.ex` | **the read path**: uses `fact`'s indices instead of scanning the ledger. Measured: 235 ms → 0.07 ms over 20,000 events |
| `state_change.ex` | the contract for a write slice: `query`, `append_condition`, `initial_state`, `apply_event`, `execute` |
| `state_view.ex` | the contract for a read slice: `query`, `initial_state`, `apply_event` |
| `fact_event.ex` | protocol: domain struct → `fact` map (`type`, `data`, **`tags`**) |
| `id.ex` | `uuid4` without pulling Ecto into the domain |

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

**Already have a project?** Decline the root files and merge four things
instead; `INSTALL.md` lists them.

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

## Three rules `slice.json` doesn't tell you

They live in `.build-kit/CLAUDE.md` and they are the reason this kit exists. You
can't derive them by reading other build kits — they came from building a slice
by hand and hitting them:

1. **Tags come from `idAttribute: true`.** `slice.json` ships `tags: []` on every
   element: they aren't empty, they're **underived**. And tags are the query keys
   for the entire system — a made-up tag doesn't fail, it silently stops finding
   events downstream.
2. **Generated fields travel on the command.** A `derived:append instant` looks
   like it's produced at write time; doing that inside `Core` breaks purity and
   leaves the decision impossible to test without a clock.
3. **Validation doesn't get split** between `Core` and `Context`. The board's
   `SPEC_ERROR` scenarios are tested against the pure `Core`, which never goes
   through `Context`.

## Loop quirks worth knowing

Not bugs in this kit — behaviour of the ralph loop that will bite you:

- **The `slice.json` the loop writes is a stub.** `fetchAndPersistSlices` uses
  the *summary* endpoint: six fields, ~230 bytes, no `fields`, no `events`, no
  `specifications`. The kit ships `.build-kit/refresh-slices.py`, and step 0 of
  `CLAUDE.md` makes checking for it mandatory. This one is easy to miss because
  the file exists and parses — it's just empty of everything that matters.
- **An idle loop may not notice a slice you mark `Planned`** if the realtime
  event doesn't arrive. Refreshing the local index unblocks it.
- **The canonical folder name keeps accents and `·`**: it's `title` with spaces
  removed, lowercased. Normalising to ASCII creates a parallel folder the loop
  never looks at.

## Provenance

Derived from building the first chapter of [NAMU](https://namupartner.com) — EUDR
traceability for Venezuelan cocoa and coffee — slice by slice, and from the base
modules of `traduka-servo`, `conecta_zen` and `contextovnzla`.

The kit was validated by using it: five real defects surfaced from running it,
none from reading it. All five are closed, in the blueprint or in the skills.

MIT.
