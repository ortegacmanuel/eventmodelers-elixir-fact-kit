defmodule MyApp.StateView do
  @moduledoc """
  Behaviour for read slices (read models), and the read that serves them.

  Pick from history, fold into current state, project what the screen gets.
  There is no table and no materialised projection: the view is computed on
  every call, by `read/3`.

    * `query/1` — what to read, from the call's arguments.
    * `next_query/1` (optional) — what else to read, given what's folded so
      far: the plots of the receptions of a lot can't be named before the lot
      is read. It returns every follow-up query the state implies; `read/3`
      reads only the ones it hasn't read yet and stops when none are new.
    * `initial_state/0`, `apply_event/2` — the fold.
    * `project/2` (optional) — the read model, from the folded state and the
      call's arguments. Without it, the state is the read model.
  """

  @callback query(args :: term()) :: term()
  @callback next_query(state :: term()) :: term() | nil
  @callback initial_state() :: term()
  @callback apply_event(state :: term(), event :: map()) :: term()
  @callback project(state :: term(), args :: term()) :: term()

  @optional_callbacks next_query: 1, project: 2

  def read(db, core, args) do
    {view, _items} = view(core, args, &MyApp.Reader.read(db, &1))
    view
  end

  @doc """
  The read with the store passed in: `core.query(args)`, then `next_query/1`
  until nothing new, the fold, and `project/2`. Returns `{view,
  every_query_item_read}`. Production reads FACT; `MyApp.Scenario` reads the
  scenario's `given`, so a test runs this same code.
  """
  def view(core, args, read) do
    Code.ensure_loaded!(core)
    first = List.wrap(core.query(args))
    {state, items} = follow(read, core, read.(first), MapSet.new(first))

    view = if function_exported?(core, :project, 2), do: core.project(state, args), else: state
    {view, MapSet.to_list(items)}
  end

  defp follow(read_fun, core, events, read) do
    state = Enum.reduce(events, core.initial_state(), &core.apply_event(&2, &1))

    new =
      if function_exported?(core, :next_query, 1),
        do: state |> core.next_query() |> List.wrap() |> Enum.reject(&MapSet.member?(read, &1)),
        else: []

    case new do
      [] ->
        {state, read}

      items ->
        events =
          (events ++ read_fun.(items))
          |> Enum.uniq_by(& &1["event_id"])
          |> Enum.sort_by(& &1["store_position"])

        follow(read_fun, core, events, MapSet.union(read, MapSet.new(items)))
    end
  end
end
