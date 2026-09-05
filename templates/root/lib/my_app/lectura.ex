defmodule MyApp.Lectura do
  @moduledoc """
  Lee del event store eligiendo el índice adecuado en vez de recorrer el ledger.

  ## El problema que resuelve

  `Fact.read(db, {:query, %Fact.QueryItem{}})` convierte la consulta en una
  función y **recorre el ledger entero** aplicándola evento a evento. Funciona,
  pero es O(n) sobre el tamaño del store. Medido en `contextovnzla`, de donde
  viene este módulo:

      consulta por etiqueta, store de    200 eventos →   1,3 ms
      consulta por etiqueta, store de 20.000 eventos → 235,0 ms
      la misma, por el índice de etiquetas           →   0,07 ms   (3.300×)

  FACT ya mantiene índices en disco (`indices/event_tags`, `indices/event_type`);
  simplemente no se usan si no se le pide. Este módulo elige el más selectivo y
  filtra en memoria lo que el índice no puede expresar.

  Importa porque **toda escritura empieza por una lectura**: `Decide` lee y
  pliega antes de decidir, y vuelve a leer para esperar la visibilidad. Sin
  esto, cada comprobación guardada se encarece según crece la historia.

  ## Cómo elige

    * **Con etiquetas** → índice de la primera etiqueta, y se filtran en memoria
      las demás y los tipos. Es el caso de casi todas las rodajas, y el que más
      gana: las etiquetas llevan ids (`comprobacion:<uuid>`), así que el índice
      devuelve un puñado de eventos en vez del store entero.
    * **Sólo tipos** → un índice por tipo y mezcla ordenada por posición. Aquí
      la ganancia no está en encontrar sino en **no leer lo ajeno**.
    * **Lo demás** (`:all`, `:none`, consultas por `data`) → el camino original.

  Sobre las consultas por `data` (`Fact.QueryItem.data/1`): **no se usan y no
  conviene empezar**. La base se crea sin indexador de datos, así que su
  comportamiento depende del estado del store — a veces devuelven vacío y a
  veces revientan. Toda la clasificación va por etiquetas, que sí están
  indexadas.

  ## Lo que no cambia

  El resultado es **idéntico** al del escaneo: mismos eventos, mismo orden por
  `store_position`, mismos campos. Eso lo afirma `test/my_app/lectura_test.exs`
  comparando las dos rutas consulta a consulta.
  """

  @doc """
  Lee los eventos que casan con `consulta`, en orden de `store_position`.

  Acepta lo mismo que `Fact.read/2` en su forma `{:query, ...}`: un
  `%Fact.QueryItem{}`, una lista de ellos (consulta compuesta, unidas con O), o
  `:all` / `:none`.
  """
  def leer(db, consulta)

  def leer(db, items) when is_list(items) do
    # Compuesta: cada item es una alternativa. Se unen y se ordena por posición
    # para que el plegado vea la misma secuencia que vería un escaneo.
    items
    |> Enum.flat_map(&leer(db, &1))
    |> Enum.uniq_by(& &1["event_id"])
    |> Enum.sort_by(& &1["store_position"])
  end

  # Las consultas por `data` no tienen índice: al camino original.
  def leer(db, %Fact.QueryItem{data: [_ | _]} = consulta), do: escanear(db, consulta)

  def leer(db, %Fact.QueryItem{tags: [etiqueta | resto], types: tipos}) do
    db
    |> Fact.read({:index, {Fact.EventTagsIndexer, nil}, etiqueta})
    |> Enum.filter(&casa?(&1, resto, tipos))
  end

  def leer(db, %Fact.QueryItem{tags: [], types: [tipo]}) do
    db |> Fact.read({:index, {Fact.EventTypeIndexer, nil}, tipo}) |> Enum.to_list()
  end

  def leer(db, %Fact.QueryItem{tags: [], types: [_ | _] = tipos}) do
    tipos
    |> Enum.flat_map(&Fact.read(db, {:index, {Fact.EventTypeIndexer, nil}, &1}))
    |> Enum.sort_by(& &1["store_position"])
  end

  def leer(db, consulta), do: escanear(db, consulta)

  defp escanear(db, consulta), do: db |> Fact.read({:query, consulta}) |> Enum.to_list()

  # Las etiquetas dentro de un QueryItem se combinan con Y y los tipos con O.
  # El índice ya resolvió la primera etiqueta; aquí se aplica el resto.
  defp casa?(evento, etiquetas, tipos) do
    tipo_ok?(evento, tipos) and etiquetas_ok?(evento, etiquetas)
  end

  defp tipo_ok?(_evento, []), do: true
  defp tipo_ok?(evento, tipos), do: evento["event_type"] in tipos

  defp etiquetas_ok?(_evento, []), do: true

  defp etiquetas_ok?(evento, etiquetas) do
    del_evento = MapSet.new(evento["event_tags"] || [])
    Enum.all?(etiquetas, &MapSet.member?(del_evento, &1))
  end
end
