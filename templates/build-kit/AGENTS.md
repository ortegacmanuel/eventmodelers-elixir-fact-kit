# What we learned building

Reusable patterns and traps, read **before every slice**: the memory that stops
mistakes repeating across iterations. It ships seeded with what came out of
building the first chapter of a real system on this framework — each one cost a
round trip. On its first run the loop adopts every line as a learning and
regenerates this file from then on: add to it with
`npx @eventmodelers/cli learn`, not by hand. A hand edit adds lines but never
removes one: correcting a line by hand leaves the old one in the log, and it
comes back. Retract it with `learn --retract <id>` (ids from `learnings --ids`).

## The framework

- `lib/my_app/`: `decide.ex`, `reader.ex`, `state_change.ex`, `state_view.ex`,
  `event.ex`, `command.ex`. **Don't touch them** unless asked.
- `Decide` waits until the write is visible before returning: `Fact.append/3`
  confirms 7–10 ms before a subsequent read can see it. Without that wait, a
  LiveView that writes and immediately repaints shows the old state.
- `Reader.read/2` reads by index instead of scanning the ledger. Measured: a
  tag query over 20,000 events, **235 ms scanning vs 0.07 ms by index**. It
  matters because every write starts with a read.
- Known ceiling, deliberately **not** solved in the base framework: with the
  append condition anchored at 0 — which is what happens when the fold finds
  nothing — FACT scans the entire ledger. Measured: 29 ms at 531 events,
  **4.5 s at 157,711**. The fix is anchoring on a visibility mark; the seam is
  documented in `Decide.read_and_fold/3`.

## About `slice.json`

- **`tags: []` doesn't mean "no tags", it means "underived".** They come from
  the fields with `idAttribute: true`. It's the most important rule in the kit.
- **A `slice.json` of ~230 bytes is the summary stub**: six fields, no `fields`, no `events`, no `specifications`, no board comments. The loop fetches the full slice before each build; if it is still a stub, `npx @eventmodelers/cli fetch --context <ctx>` (step 0 in `CLAUDE.md`).
- The canonical folder name is `title` with spaces removed, lowercased,
  **keeping accents and `·`**. Normalising to ASCII creates a parallel folder
  the loop never looks at.
- The screen arrives as metadata: `title`, `fields`, `dependencies` and prose.
  **The rendered design does not travel in the payload.**
- Each node's `description` carries the invariants written out in prose, and
  often explains **which rules were removed and why**. It's the most valuable
  thing in the file and the easiest to skip.
- The scenarios' `examples` are often **measured against real systems**. If a
  test fails, suspect the test before the data.

## FACT and quality-gate traps

- **`event_data` comes back with string keys in snake_case.** Events are
  serialised with `Map.from_struct/1`, so a `checkId` on the board reads as
  `d["check_id"]`. You can confirm by looking at the files under
  `data/fact_db/events/<xx>/<id>` — they're plain JSON.
- **The store must exist before boot.** If it doesn't, `Application.fact_db/0`
  **raises** after two seconds and takes down whatever the user was doing. That's
  why `fact.setup` is in the aliases for `test`, `setup` **and** `phx.server`.
- **`mix precommit` compiles with `--warnings-as-errors`.** A
  `defp f(x, y \\ %{})` whose default is never used is a warning, and it fails
  the gate.

## About tests

- **Never compare `Map.keys/1` against a list.** The order isn't guaranteed:
  `assert Map.keys(row) == [:a, :b, :c]` fails **intermittently** — it passes
  locally and breaks the gate later. It got committed that way once. Use
  `MapSet`.
- A passing test can be lying. One asserted that a button starts disabled — true
  only because there's no JavaScript in tests to publish the initial state.
  **When a test depends on something the browser does on its own, simulate it
  explicitly.**
- `Application.put_env` is global. A test that mutates it **can't live in an
  `async: true` module** alongside another that reads the same config.
- With `nil`, HEEx **omits the attribute entirely** rather than rendering it
  empty, so the obvious assertion (`data-x=''`) matches nothing.

## About read slices

- **A TODO queue isn't scoped by tag.** It's the exception to "the tag scopes
  the view": its consumer is a processor, which has no session or any other
  identity to filter by. The query goes by types.
- **The expensive failure is a type missing from `query/1`.** It doesn't blow
  up: it leaves the field `nil` forever and nobody notices. Worth a test on
  `query/1` itself — the types and the tags — because the rest of the suite
  passes just the same with a wrong query.
- **A queue with no status field is a decision, not an oversight.** Membership
  of the list *is* the status.

## About the loop

- **The loop owns the slice's status**: it claims the slice before the build and pushes the outcome after. Record the outcome with `npx @eventmodelers/cli slice-status Done`; calling `update-slice-status` yourself makes the board's change come back as a queued task and costs a whole extra turn.
- Two loops on the same directory share `index.json` and the working tree, and each wants its own branch in the same checkout. If you run them in parallel, **one worktree per agent**.
- An idle loop may not notice a slice marked `Planned` if the realtime event
  doesn't arrive. Refreshing the local index unblocks it.

## The screen brief

- If the slice has `screens`, alongside the domain you write
  `docs/screens/<slice>.md`. Template and rules in `.build-kit/CLAUDE.md`.
- **The section that earns its keep is "What the domain does NOT give you".**
  It's what stops whoever builds the view from inventing fields or asking the
  domain for them without cause. Write it even if the rest ends up short.
- The **error atoms** from the `Decider` always go in: the screen translates them into
  messages and can't guess them from `slice.json`.
- It lives in `docs/` and not `.build-kit/` on purpose: `.build-kit/` is
  regenerated on every fetch and the brief has to survive.
