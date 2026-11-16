defmodule MyApp.Scenario do
  @moduledoc """
  The board's scenarios as tests: `given`, then `decide` or `read`, then
  `expect`.

      import MyApp.Scenario

      # a write slice
      given([%LotOpened{lot_id: "L-1"}])
      |> decide(Decider, %CloseLot{lot_id: "L-1"})
      |> expect({:ok, [%LotClosed{lot_id: "L-1"}]})

      # a read slice
      given([%PlotRegistered{plot_id: "P-1", name: "La Vega"}])
      |> read(ReadModel, "P-1")
      |> expect(%{name: "La Vega"})

  ## Why not fold the `given` by hand

  In production a decision only sees what its `query/1` reads. Folding the
  `given` straight into `apply_event/2` skips that read, so a query that forgets
  a type, asks for the wrong tag or misses a follow-up passes every test and
  silently never fires. Here the `given` is the store:

    * `given/1` stores each event the way `MyApp.Decide` appends it: through
      `MyApp.Event.to_event/1`, so its tags are the production ones, and through
      JSON, so `apply_event/2` gets the same string-keyed data it gets from FACT.
    * `decide/3` and `read/3` run the production loop (`MyApp.Decide.fold/3`,
      `MyApp.StateView.view/3`) reading that store with `MyApp.Reader.selects?/2`,
      the same match `MyApp.Reader` applies.
    * `expect/2` matches the result against a pattern. When it fails and some
      `given` events were never read, it says which: a scenario may include an
      event on purpose to show it's ignored, so being unread is a hint, not a
      failure by itself.

  ## The `given`

  An event struct — the normal case. An event no code writes any more (it's
  still in the store) or that comes from outside has no struct: give it as the
  shape FACT appends, `%{type: "…", data: %{…}, tags: ["…"]}`, plus `id: "…"`
  when the fold keys on the event id.
  """

  import ExUnit.Assertions

  defstruct store: [], value: nil, read: []

  @doc "Stores the scenario's `given` events, in order."
  def given(events) do
    store =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {event, position} -> record(event, position) end)

    %__MODULE__{store: store}
  end

  @doc "Runs a write slice's decision against the `given`."
  def decide(%__MODULE__{store: store} = scenario, decider, cmd) do
    {state, _last, _first, items} = MyApp.Decide.fold(decider, cmd, &select(store, &1))
    %{scenario | value: decider.execute(cmd, state), read: items}
  end

  @doc "Computes a read slice's view from the `given`."
  def read(%__MODULE__{store: store} = scenario, read_model, args) do
    {view, items} = MyApp.StateView.view(read_model, args, &select(store, &1))
    %{scenario | value: view, read: items}
  end

  @doc """
  Asserts the result matches `pattern` (a struct or map pattern matches the keys
  it names). Returns the result.
  """
  defmacro expect(scenario, pattern) do
    quote do
      %MyApp.Scenario{value: value} = scenario = unquote(scenario)

      try do
        assert unquote(pattern) = value
      rescue
        error in ExUnit.AssertionError ->
          reraise %{error | message: error.message <> MyApp.Scenario.unread(scenario)},
                  __STACKTRACE__
      end

      value
    end
  end

  @doc false
  def unread(%__MODULE__{store: store, read: items}) do
    case Enum.reject(store, &MyApp.Reader.selects?(items, &1)) do
      [] ->
        ""

      unread ->
        lines = Enum.map_join(unread, "\n", &"  #{&1["event_type"]} #{inspect(&1["event_tags"])}")

        "\n\nThese given events were never read — the slice's queries don't select them:\n" <>
          lines
    end
  end

  defp select(store, query), do: Enum.filter(store, &MyApp.Reader.selects?(query, &1))

  defp record(%_{} = event, position), do: record(MyApp.Event.to_event(event), position)

  defp record(%{type: type} = event, position) do
    %{
      "event_id" => Map.get(event, :id, "given-#{position}"),
      "event_type" => type,
      "event_data" => event |> Map.get(:data, %{}) |> Jason.encode!() |> Jason.decode!(),
      "event_tags" => Map.get(event, :tags, []),
      "event_metadata" => %{},
      "store_position" => position
    }
  end
end
