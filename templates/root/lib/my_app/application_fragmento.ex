# ─────────────────────────────────────────────────────────────────────────────
#  NO es un fichero completo: son los dos trozos que hay que añadir al
#  `application.ex` que genera `mix phx.new`. Bórralo cuando los hayas copiado.
# ─────────────────────────────────────────────────────────────────────────────

#  1) En `start/2`, dentro de `children`, ANTES del Endpoint:

    fact_path = Application.get_env(:my_app, :fact_path, "data/fact_db")

    children = [
      MyAppWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyApp.PubSub},
      # El event store: ficheros, sin base de datos.
      {Fact.Supervisor, databases: [fact_path]},
      # Para el trabajo de rodaja que no debe bloquear la petición — las
      # llamadas externas de los procesadores.
      {Task.Supervisor, name: MyApp.TaskSupervisor},
      MyAppWeb.Endpoint
    ]

#  2) Como función pública del módulo:

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
