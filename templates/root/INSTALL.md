# After installing

**This file is meant to be read and deleted.**

The kit ships a working project: `mix.exs`, `config/`, the supervision tree and
the framework. It compiles and `mix precommit` passes as installed. There is one
thing to do, and one case that needs care.

---

## 1 · Rename the namespace

The CLI copies files without templating, so everything ships as `MyApp` /
`my_app`:

```bash
APP=my_app; MOD=MyApp   # ← change these two to yours
grep -rl 'MyApp\|my_app' lib config test mix.exs README.md \
  .claude/skills .build-kit/CLAUDE.md \
  | xargs sed -i "s/MyApp/$MOD/g; s/my_app/$APP/g"
mv lib/my_app "lib/$APP"
```

Then:

```bash
mix setup && mix precommit
```

Green? Delete this file and start marking slices `Planned` on the board.

---

## 2 · If you already have a project

Don't take the root files — they'd overwrite yours. Decline them, or install
into an empty directory and copy across only what you need:

**Always:** `lib/my_app/*.ex`, the framework itself.

**Merge into your `mix.exs`:**

```elixir
{:fact, "~> 0.2.0"},
{:req, "~> 0.5"},           # only if a slice calls an external system
```

```elixir
def cli, do: [preferred_envs: [precommit: :test]]
```

…and the aliases, where **`fact.setup` must appear in `setup` and in `test`** —
plus `phx.server` if you run Phoenix. Without the store created,
`Application.fact_db/0` raises after two seconds and takes down whatever the
caller was doing. It is a slow thing to diagnose.

**Merge into your `Application.start/2`,** before your Endpoint:

```elixir
{Fact.Supervisor, databases: [Application.get_env(:my_app, :fact_path, "data/fact_db")]},
{Task.Supervisor, name: MyApp.TaskSupervisor},
```

**And copy `fact_db/0` and `ledger_alive?/1`** from the shipped
`application.ex` into yours. The retry is not decoration: FACT registers the
context before the ledger takes the file lock, so an id returned in between
looks fine and blows up on the first append.

**Config:** `fact_path` per environment — and **absolute in production**, since
a release starts with its cwd inside its own `bin/`.

---

## 3 · Phoenix

Not required. The framework is pure domain — it depends on `Logger` and `fact`
and nothing else — and this kit does not build screens. Add Phoenix when you
want a UI, and keep it out of `lib/<app>/`.
