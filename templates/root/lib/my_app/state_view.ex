defmodule MyApp.StateView do
  @moduledoc """
  Comportamiento de las rodajas de lectura (modelos de lectura).

  Elegir de la historia y plegar hasta el estado actual.
  """

  @callback query(context :: term()) :: term()
  @callback initial_state() :: term()
  @callback apply_event(state :: term(), event :: map()) :: term()
end
