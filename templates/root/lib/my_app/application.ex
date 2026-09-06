defmodule MyApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    fact_path = Application.get_env(:my_app, :fact_path, "data/fact_db")

    children = [
      MyAppWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyApp.PubSub},
      # Start a worker by calling: MyApp.Worker.start_link(arg)
      # {MyApp.Worker, arg},
      # Start to serve requests, typically the last entry
      # The event store: files, no database. Before the Endpoint, so nothing can
      # serve a request against a store that isn't up.
      {Fact.Supervisor, databases: [fact_path]},
      # For slice work that must not block the caller — an automation slice's
      # external calls run as tasks under here.
      {Task.Supervisor, name: MyApp.TaskSupervisor},
      MyAppWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  The FACT database id, looked up in the registry with no GenServer in the way.

  It also waits for the `Fact.EventLedger` to be alive, not just for the id to
  appear. FACT boots in two steps: first the context is registered — and there
  is already an id — then the ledger starts and takes the file lock. Returning
  the id in between looks like it works and blows up on the first `Fact.append`
  with a "no process".
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
        raise "the FACT database did not start in time " <>
                "(no id and no ledger after #{@attempts * @wait_ms} ms)"
    end
  end

  # The per-database registry is also created during boot, so there's an instant
  # where it doesn't even exist. `Registry.lookup/2` on a registry that doesn't
  # exist *raises* rather than returning an empty list — hence the `whereis`
  # first.
  defp ledger_alive?(db) do
    registry = Fact.Registry.registry(db)

    case Process.whereis(registry) do
      nil -> false
      _pid -> match?([{_pid, _}], Registry.lookup(registry, Fact.EventLedger))
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MyAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
