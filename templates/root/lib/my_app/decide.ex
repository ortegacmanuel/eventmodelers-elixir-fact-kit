defmodule MyApp.Decide do
  @moduledoc """
  El motor de toda escritura: leer → plegar → decidir → añadir, con DCB y
  concurrencia optimista.

  Ante un conflicto de concurrencia repite el ciclo entero (releer, replegar,
  redecidir, reañadir).

  ## Leer lo que acabas de escribir

  `Fact.append/3` confirma el añadido unos milisegundos antes de que el evento
  sea visible para una lectura posterior (medido en `contextovnzla`: 7–10 ms).
  La comprobación de parcelas es una LiveView que escribe y **acto seguido**
  vuelve a leer para repintar: sin esperar, el visitante suelta el pin y la
  página le sigue diciendo que no hay nada.

  Por eso `execute/4` no vuelve hasta que el evento que acaba de escribir se ve
  en una lectura. La espera se hace aquí, en el único sitio por el que pasan
  todas las escrituras, en vez de repartir esperas por los manejadores. Cuesta
  unos milisegundos por comando, y a cambio todo lo de arriba puede dar por
  hecho que lo que escribió ya está.

  ## Dónde se ancla la condición de añadido, y el techo que tiene

  El añadido va condicionado: «falla si apareció algún evento que case con esta
  consulta **después de la posición P**». Hoy `P` es la posición del último
  evento plegado, que vale **0** cuando no hay nada que plegar — y en una
  comprobación nueva ése es el caso normal, porque nadie ha escrito antes sobre
  esa parcela.

  Ante `P = 0`, FACT recorre el ledger **entero** aplicando la consulta, dentro
  del `handle_call` del único proceso que escribe. Es lineal sobre la historia
  acumulada. Medido en `contextovnzla`:

      ledger de     531 eventos → decidir  29 ms
      ledger de   7.591 eventos → decidir 256 ms
      ledger de  37.651 eventos → decidir  1,1 s
      ledger de 157.711 eventos → decidir  4,5 s

  **Aquí no duele todavía**, y por eso no está resuelto: NAMU escribe tres
  eventos por comprobación y las inicia una persona, así que llegar a esas
  cifras son decenas de miles de comprobaciones. A 531 eventos son 29 ms.

  Cuando duela, la solución ya está escrita en `contextovnzla`
  (`lib/contexto_vnzla/visibilidad.ex`) y **la costura es esta función**:
  `read_and_fold/3` devuelve el ancla, y basta con que devuelva
  `max(MyApp.Visibilidad.hasta(db), ultima)` en vez de `ultima`. La marca hay que
  pedirla **antes** de leer, no después: así todo lo que la lectura pueda
  devolver queda por debajo de ella y la condición sigue vigilando de la marca
  en adelante, que es donde estaría el escritor concurrente. Con eso, la misma
  decisión sobre 157.711 eventos baja de 4,5 s a 8 ms.

  Y el ancla no puede ser la cabeza del ledger: `MyApp.Lectura` lee por índice, y
  los índices de FACT se mantienen de forma asíncrona — anclar en la cabeza
  sería afirmar haber visto eventos que el índice todavía no publicaba.
  """

  require Logger

  @max_retries 3

  # Cota de la espera de visibilidad. El retardo medido ronda los 10 ms; 2 s es
  # un margen absurdo a propósito, para que sólo se agote si algo va muy mal.
  @visibilidad_intentos 400
  @visibilidad_espera_ms 5

  def execute(db, core, cmd, opts \\ []) do
    extra_tags = Keyword.get(opts, :extra_tags, [])
    retries = Keyword.get(opts, :retries, @max_retries)

    do_execute(db, core, cmd, extra_tags, retries)
  end

  defp do_execute(db, core, cmd, extra_tags, retries) do
    {state, last_position} = read_and_fold(db, core, cmd)

    case core.execute(cmd, state) do
      {:ok, events} ->
        fact_events =
          events
          |> Enum.map(&MyApp.FactEvent.to_fact/1)
          |> append_extra_tags(extra_tags)

        condition = {core.append_condition(cmd), last_position}

        case Fact.append(db, fact_events, condition) do
          {:ok, position} ->
            esperar_visibilidad(db, fact_events, position)
            {:ok, events}

          {:error, %Fact.ConcurrencyError{}} when retries > 0 ->
            Logger.debug("conflicto de concurrencia, reintentando (quedan #{retries})")
            do_execute(db, core, cmd, extra_tags, retries - 1)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Espera a que los eventos recién añadidos aparezcan en una lectura.
  #
  # La consulta se construye a partir de los propios eventos (su tipo y sus
  # etiquetas), no de `core.query/1`: hay rodajas cuya consulta de decisión no
  # incluye el tipo que emiten, y esperar sobre esa consulta no vería nunca lo
  # escrito. Como las etiquetas llevan siempre un id único
  # (`comprobacion:<uuid>`), la consulta devuelve un puñado de eventos y la
  # espera es barata.
  defp esperar_visibilidad(db, fact_events, position) do
    consulta =
      fact_events
      |> Enum.map(fn e -> Fact.QueryItem.types([e.type]) |> Fact.QueryItem.tags(e.tags) end)
      |> Fact.QueryItem.join()

    esperar(db, consulta, position, @visibilidad_intentos)
  end

  defp esperar(_db, _consulta, position, 0) do
    Logger.warning("el evento en la posición #{position} no se hizo visible a tiempo")
    :timeout
  end

  defp esperar(db, consulta, position, intentos) do
    visible =
      db
      |> MyApp.Lectura.leer(consulta)
      |> Enum.reduce(0, fn event, maximo -> max(event["store_position"] || 0, maximo) end)

    if visible >= position do
      :ok
    else
      Process.sleep(@visibilidad_espera_ms)
      esperar(db, consulta, position, intentos - 1)
    end
  end

  # Devuelve el estado plegado y el ancla para la condición de añadido.
  # Ver el moduledoc: el ancla es hoy la posición del último evento plegado, y
  # aquí es donde se sube a la marca de visibilidad cuando el ledger crezca.
  defp read_and_fold(db, core, cmd) do
    MyApp.Lectura.leer(db, core.query(cmd))
    |> Enum.reduce({core.initial_state(), 0}, fn event, {state, _pos} ->
      {core.apply_event(state, event), event["store_position"] || 0}
    end)
  end

  defp append_extra_tags(fact_events, []), do: fact_events

  defp append_extra_tags(fact_events, extra_tags) do
    Enum.map(fact_events, fn event ->
      Map.update(event, :tags, extra_tags, &(&1 ++ extra_tags))
    end)
  end
end
