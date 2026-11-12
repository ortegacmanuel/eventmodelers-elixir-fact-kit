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
    `region: [:address, "regionId"]` gives `"region:<value>"`. A tag whose
    value is nil is left out.

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
        value = get_in(event, [Access.key(field) | path]),
        value != nil,
        do: "#{name}:#{value}"
  end
end
