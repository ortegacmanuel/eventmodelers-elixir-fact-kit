defmodule MyApp.StateView do
  @moduledoc """
  Behaviour for read slices (read models).

  Pick from history, fold into current state. There is no table and no
  materialised projection: the view is computed on every call.
  """

  @callback query(context :: term()) :: term()
  @callback initial_state() :: term()
  @callback apply_event(state :: term(), event :: map()) :: term()
end
