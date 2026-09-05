# Installing the framework

Four steps after `npx @eventmodelers/cli init --stack elixir-fact --git …`.

**This file is meant to be read and deleted.** It's Markdown on purpose: if it
were a `.ex` inside `lib/`, `mix compile` would try to compile it and the project
wouldn't boot — these are fragments, not modules.

And if you don't have a project yet:

```bash
mix phx.new my_app --no-ecto
```

`--no-ecto` because the domain has no database. If you need Ecto for something
else — forms via `phoenix_ecto`, a throwaway mirror of an external system — add
it later, but **keep it out of the domain**.

---

## 1 · Rename the namespace

The CLI copies files without templating, so the framework ships as `MyApp`:

```bash
APP=my_app; MOD=MyApp   # ← change these two to yours
grep -rl 'MyApp\|my_app' lib .claude/skills .build-kit/CLAUDE.md \
  | xargs sed -i "s/MyApp/$MOD/g; s/my_app/$APP/g"
mv lib/my_app "lib/$APP"
```

---

## 2 · `mix.exs`

Dependencies:

```elixir
{:fact, "~> 0.2.0"},
{:req, "~> 0.5"},
# PINNED version: the latest may not ship a precompiled binary for your
# platform and falls back to building lexbor with cmake.
{:lazy_html, "0.1.11", only: :test},
```

And the aliases. **`fact.setup` goes in all three**: without the store created,
`Application.fact_db/0` raises after two seconds and takes down whatever the user
was doing. It happens the first time someone runs `phx.server`, and it takes a
while to diagnose.

```elixir
defp aliases do
  [
    setup: ["deps.get", "fact.setup", "assets.setup", "assets.build"],
    test: ["fact.setup", "test"],
    "phx.server": ["fact.setup", "phx.server"],
    "fact.setup": &fact_setup/1,
    precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
  ]
end

defp fact_setup(_) do
  fact_path = Application.get_env(:my_app, :fact_path, "data/fact_db")

  unless File.exists?(Path.join(fact_path, ".bootstrap")) do
    Mix.Task.run("fact.create", ["--path", fact_path, "--name", "fact_db"])
  end
end
```

---

## 3 · `application.ex`

In `start/2`, inside `children` and **before** the Endpoint:

```elixir
fact_path = Application.get_env(:my_app, :fact_path, "data/fact_db")

children = [
  MyAppWeb.Telemetry,
  {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: MyApp.PubSub},
  # The event store: files, no database.
  {Fact.Supervisor, databases: [fact_path]},
  # For slice work that must not block the request — the processors' external
  # calls.
  {Task.Supervisor, name: MyApp.TaskSupervisor},
  MyAppWeb.Endpoint
]
```

And as a public function of the same module:

```elixir
@doc """
Returns the FACT database id, looked up in the registry with no GenServer in
the way.

It also waits for the `Fact.EventLedger` to be alive, not just for the id to
appear. FACT boots in two steps: first the context is registered (and there is
already an id), then the ledger starts and takes the file lock. Returning the id
in between looks like it works and blows up on the first `Fact.append` with a
"no process".
"""
@attempts 100
@wait_ms 20

def fact_db(attempts \\ @attempts) do
  with {:ok, db} <- Fact.Registry.get_database_id("fact_db"),
       true <- ledger_alive?(db) do
    db
  else
    _ when attempts > 0 ->
      Process.sleep(@wait_ms)
      fact_db(attempts - 1)

    _ ->
      raise "the FACT database did not start in time (no id and no ledger after #{@attempts * @wait_ms} ms)"
  end
end

# The per-database registry is also created during boot, so there's an instant
# where it doesn't even exist. `Registry.lookup/2` on a registry that doesn't
# exist *raises* rather than returning an empty list — hence the `whereis` first.
defp ledger_alive?(db) do
  registry = Fact.Registry.registry(db)

  case Process.whereis(registry) do
    nil -> false
    _pid -> match?([{_pid, _}], Registry.lookup(registry, Fact.EventLedger))
  end
end
```

---

## 4 · `config/`

```elixir
# config/dev.exs
config :my_app, fact_path: "data/fact_db"

# config/test.exs — a separate store, so it doesn't mix with development.
config :my_app, fact_path: "data/test/fact_db"

# config/runtime.exs, inside the production block
config :my_app, :fact_path, System.get_env("FACT_PATH") || "/opt/my_app/data/fact_db"
```

---

## Done

```bash
mix deps.get && mix precommit
```

Once it's green, **delete this file** and start marking slices `Planned` on the
board.
