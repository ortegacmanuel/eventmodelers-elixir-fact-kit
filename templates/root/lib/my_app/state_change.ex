defmodule MyApp.StateChange do
  @moduledoc """
  Comportamiento de las rodajas de escritura (patrón Decider con DCB).

  Elegir de la historia, plegar hasta el estado actual, decidir el comando →
  eventos nuevos o rechazo.

  ## Condiciones de añadido (DCB)

  `query/1` define qué eventos se leen (SourcingCriteria).
  `append_condition/1` define qué eventos concurrentes invalidarían la decisión
  (AppendCriteria).

  Por defecto `append_condition/1` cae en `query/1` — simétrico, que es el valor
  seguro. Se sobreescribe cuando los eventos concurrentes sólo pueden reforzar
  el invariante y no deberían provocar conflicto (DCB asimétrico).
  """

  @callback query(command :: term()) :: term()
  @callback append_condition(command :: term()) :: term()
  @callback initial_state() :: term()
  @callback apply_event(state :: term(), event :: map()) :: term()
  @callback execute(command :: term(), state :: term()) :: {:ok, [term()]} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour MyApp.StateChange

      @doc false
      def append_condition(cmd), do: query(cmd)

      defoverridable append_condition: 1
    end
  end
end
