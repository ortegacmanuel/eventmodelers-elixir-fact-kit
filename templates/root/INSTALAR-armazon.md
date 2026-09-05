# Instalar el armazón

Cuatro pasos después de `npx @eventmodelers/cli init --stack elixir-fact --git …`.

**Este fichero es para leer y borrar.** Va en Markdown a propósito: si fuera un
`.ex` dentro de `lib/`, `mix compile` intentaría compilarlo y el proyecto no
arrancaría — son trozos sueltos, no módulos.

Y si todavía no hay proyecto:

```bash
mix phx.new mi_app --no-ecto
```

`--no-ecto` porque el dominio no usa base de datos. Si necesitas Ecto para otra
cosa —formularios vía `phoenix_ecto`, un espejo desechable de un sistema
externo— añádelo después, pero **fuera del dominio**.

---

## 1 · Renombrar el namespace

El CLI copia ficheros sin sustituir plantillas, así que el armazón viene como
`MyApp`:

```bash
APP=mi_app; MOD=MiApp
grep -rl 'MyApp\|my_app' lib .claude/skills .build-kit/CLAUDE.md \
  | xargs sed -i "s/MyApp/$MOD/g; s/my_app/$APP/g"
mv lib/my_app "lib/$APP"
```

---

## 2 · `mix.exs`

```elixir
{:fact, "~> 0.2.0"},
{:req, "~> 0.5"},
# Versión CLAVADA: la última puede no traer binario precompilado para tu
# plataforma y cae a compilar lexbor con cmake.
{:lazy_html, "0.1.11", only: :test},
```

Y los alias. **`fact.setup` va en los tres**: sin el store creado,
`Application.fact_db/0` lanza tras dos segundos y se lleva por delante lo que
estuviera haciendo el usuario. Pasa la primera vez que alguien arranca
`phx.server`, y cuesta un rato diagnosticarlo.

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
  fact_path = Application.get_env(:mi_app, :fact_path, "data/fact_db")

  unless File.exists?(Path.join(fact_path, ".bootstrap")) do
    Mix.Task.run("fact.create", ["--path", fact_path, "--name", "fact_db"])
  end
end
```

---

## 3 · `application.ex`

En `start/2`, dentro de `children` y **antes** del Endpoint:

```elixir
fact_path = Application.get_env(:mi_app, :fact_path, "data/fact_db")

children = [
  MiAppWeb.Telemetry,
  {DNSCluster, query: Application.get_env(:mi_app, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: MiApp.PubSub},
  # El event store: ficheros, sin base de datos.
  {Fact.Supervisor, databases: [fact_path]},
  # Para el trabajo de rodaja que no debe bloquear la petición — las llamadas
  # externas de los procesadores.
  {Task.Supervisor, name: MiApp.TaskSupervisor},
  MiAppWeb.Endpoint
]
```

Y como función pública del mismo módulo:

```elixir
@doc """
Devuelve el identificador de la base de FACT buscándolo en el registro, sin
GenServer de por medio.

Espera a que el `Fact.EventLedger` esté vivo, no sólo a que el identificador
aparezca. El arranque de FACT tiene dos pasos: primero se inscribe el contexto
(y ya hay id) y después arranca el ledger y toma el bloqueo del fichero.
Devolver el id entre medias parece funcionar y revienta en el primer
`Fact.append` con un «no process».
"""
@intentos 100
@espera_ms 20

def fact_db(intentos \\ @intentos) do
  with {:ok, db} <- Fact.Registry.get_database_id("fact_db"),
       true <- ledger_vivo?(db) do
    db
  else
    _ when intentos > 0 ->
      Process.sleep(@espera_ms)
      fact_db(intentos - 1)

    _ ->
      raise "la base de FACT no arrancó a tiempo (ni id ni ledger tras #{@intentos * @espera_ms} ms)"
  end
end

# El registro por base también se crea durante el arranque, así que hay un
# instante en el que ni siquiera existe. `Registry.lookup/2` sobre un registro
# inexistente *lanza*, no devuelve lista vacía — de ahí el `whereis` previo.
defp ledger_vivo?(db) do
  registro = Fact.Registry.registry(db)

  case Process.whereis(registro) do
    nil -> false
    _pid -> match?([{_pid, _}], Registry.lookup(registro, Fact.EventLedger))
  end
end
```

---

## 4 · `config/`

```elixir
# config/dev.exs
config :mi_app, fact_path: "data/fact_db"

# config/test.exs — store aparte, para no mezclarlo con el de desarrollo.
config :mi_app, fact_path: "data/test/fact_db"

# config/runtime.exs, dentro del bloque de producción
config :mi_app, :fact_path, System.get_env("FACT_PATH") || "/opt/mi_app/data/fact_db"
```

---

## Y ya

```bash
mix deps.get && mix precommit
```

Cuando compile en verde, **borra este fichero** y empieza a marcar rodajas como
`Planned` en el tablero.
