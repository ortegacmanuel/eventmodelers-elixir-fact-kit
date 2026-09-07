# After installing

**This file is meant to be read and deleted.**

The kit ships a working Phoenix project: `mix.exs`, `config/`, endpoint,
router, layouts, assets, and the FACT framework already wired into the
supervision tree. It compiles and `mix precommit` passes as installed — five
tests, the ones Phoenix generates.

There is one thing to do, and one case that needs care.

---

## 1 · Rename the namespace

The CLI copies files without templating, so everything ships as `MyApp` /
`my_app`:

```bash
APP=my_app; MOD=MyApp   # ← change these two to yours
grep -rl 'MyApp\|my_app' lib config test assets mix.exs README.md AGENTS.md \
  .claude/skills .build-kit/CLAUDE.md 2>/dev/null \
  | xargs sed -i "s/MyApp/$MOD/g; s/my_app/$APP/g"
mv lib/my_app "lib/$APP"
mv lib/my_app_web "lib/${APP}_web"
mv lib/my_app.ex "lib/$APP.ex"
mv lib/my_app_web.ex "lib/${APP}_web.ex"
```

Then:

```bash
mix setup && mix precommit
```

**On OTP 27, run `./scripts/ensure-asset-binaries.sh` first.** GitHub's release
CDN serves a certificate OTP rejects with `key_usage_mismatch`, so
`mix tailwind.install` dies with "Unsupported Certificate" — and it surfaces as
a runtime error the first time you open a page, with the endpoint already up
and serving, so it doesn't look like a build problem at all. The script pulls
the same binaries with `curl`, which uses the system trust store. Idempotent.

Green? Delete this file and start marking slices `Planned` on the board.

---

## 2 · If you already have a project — **don't run `init`**

`init` copies `templates/root/` over your project **before** it asks anything.
The only prompt is about `.build-kit/`, and by then `mix.exs`, `config/`,
`AGENTS.md`, `README.md` and the assets have already been overwritten. Asking
you to "decline the root files" is advice that arrives too late.

So: install into an empty directory, and copy across what you want. What
follows is what you want.

Don't take the root files — they'd overwrite yours. Decline them, or install
into an empty directory and copy across only what you need:

**Always:** `lib/my_app/{decide,reader,state_change,state_view,fact_event,id}.ex`
— the framework itself — and `docs/screens/`.

**Merge into your `mix.exs`:**

```elixir
{:fact, "~> 0.2.0"},
{:req, "~> 0.5"},                    # only if a slice calls an external system
{:lazy_html, "0.1.11", only: :test}, # pinned — see the comment in the shipped mix.exs
```

```elixir
def cli, do: [preferred_envs: [precommit: :test]]
```

…and the aliases, where **`fact.setup` must appear in `setup`, `test` and
`phx.server`**. Without the store created, `Application.fact_db/0` raises after
two seconds and takes down whatever the caller was doing. The first time it
bites is on `mix phx.server`, where it reads like a LiveView crash.

**Merge into your `Application.start/2`,** before the Endpoint:

```elixir
{Fact.Supervisor, databases: [Application.get_env(:my_app, :fact_path, "data/fact_db")]},
{Task.Supervisor, name: MyApp.TaskSupervisor},
```

**And copy `fact_db/0` and `ledger_alive?/1`** from the shipped
`application.ex`. The retry is not decoration: FACT registers the context
before the ledger takes the file lock, so an id returned in between looks fine
and blows up on the first append.

**Config:** `fact_path` per environment — and **absolute in production**, since
a release starts with its cwd inside its own `bin/`.
