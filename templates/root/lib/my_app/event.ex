defprotocol MyApp.Event do
  @moduledoc """
  A domain event, declared on its struct:

      @derive {MyApp.Event,
               type: "PlotRegistered",
               tags: [:plot_id, :owner_id, region: [:address, "regionId"]]}
      defstruct [:plot_id, :owner_id, :address, :registered_at]

  * `type` is the event's title on the board, verbatim. It is what the store
    keeps and what other slices match on, so it never comes from the module
    name: renaming a module must not rename a fact.
  * `tags` are the board's fields with `idAttribute: true` or `tag: true`.
    `:plot_id` gives `"plot:<value>"`. A subfield goes by its path:
    `region: [:address, "regionId"]` gives `"region:<value>"`. Through a list,
    one tag per element: `lot: [:lots, :lot_id]`. A nil value gives no tag.

  `to_event/1` returns `%{type:, data:, tags:}`, the shape FACT and UmaDB both
  store.
  """

  def to_event(event)
end

defimpl MyApp.Event, for: Any do
  defmacro __deriving__(module, _struct, opts) do
    type = Keyword.fetch!(opts, :type)

    tags =
      for tag <- Keyword.get(opts, :tags, []) do
        case tag do
          {name, [_ | _] = path} ->
            {to_string(name), path}

          field when is_atom(field) ->
            {field |> to_string() |> String.replace_suffix("_id", ""), [field]}
        end
      end

    quote do
      defimpl MyApp.Event, for: unquote(module) do
        def to_event(event) do
          %{
            type: unquote(type),
            data: Map.from_struct(event),
            tags: MyApp.Event.Any.tags(event, unquote(Macro.escape(tags)))
          }
        end

        def spec, do: %{type: unquote(type), tags: unquote(Enum.map(tags, &elem(&1, 0)))}
      end
    end
  end

  def to_event(event), do: raise(Protocol.UndefinedError, protocol: MyApp.Event, value: event)

  @doc false
  def tags(event, specs) do
    for {name, [field | path]} <- specs,
        value <- values(Map.get(event, field), path),
        uniq: true,
        do: "#{name}:#{value}"
  end

  defp values(nil, _path), do: []
  defp values(list, path) when is_list(list), do: Enum.flat_map(list, &values(&1, path))
  defp values(value, []), do: [value]
  defp values(map, [key | rest]) when is_map(map), do: values(Map.get(map, key), rest)
  defp values(_value, _path), do: []
end
