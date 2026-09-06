# my_app

Domain built from an [eventmodelers.ai](https://app.eventmodelers.ai) board:
each slice becomes Elixir, with event sourcing over
[FACT](https://hexdocs.pm/Fact) — files, no database.

Rename `my_app` / `MyApp` to your own before anything else. See `INSTALL.md`.

## Getting started

```bash
mix setup      # deps + create the event store
mix precommit  # compile --warnings-as-errors, format, test
```

Then mark a slice `Planned` on the board and start the loop:

```bash
node .build-kit/ralph-claude.js
```

## Layout

```
lib/my_app/
  application.ex   supervision tree · fact_db/0
  decide.ex        the DCB write path: query, fold, decide, append
  reader.ex        the read path
  state_change.ex  what a command-handler slice uses
  state_view.ex    what a projection slice uses
  fact_event.ex    domain event ⇄ FACT record
  id.ex            identifiers and instants, in one place
  slices/<slice>/  one directory per slice — the loop writes here
docs/screens/      screen briefs: what this kit hands to whoever builds the UI
```

**This kit builds the domain, not the screens.** When a slice has `screens`, the
loop writes a brief to `docs/screens/<slice>.md` and stops. There's a worked
example in that directory — read it before deleting it.

## Two things that will bite you

**Keep the project path short.** FACT takes its lock through a Unix domain
socket, and those cap at ~104 characters. A deep path fails at boot with a
`Fact.Database … :einval` that says nothing about the real cause.

**A release runs no mix aliases.** `fact.setup` is wired into `setup` and
`test`, so development and CI create the store on their own — but a deployment
does not. Create it as an explicit deploy step, before the release starts, or
the node comes up, serves happily, and every write fails.
