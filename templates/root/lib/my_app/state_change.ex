defmodule MyApp.StateChange do
  @moduledoc """
  Behaviour for write slices (the Decider pattern with DCB).

  Pick from history, fold into current state, execute the command → new events
  or a rejection.

  ## DCB append conditions

  `query/1` defines which events to read (SourcingCriteria).
  `append_condition/1` defines which concurrent events would invalidate the
  decision (AppendCriteria).

  By default `append_condition/1` falls back to `query/1` — symmetric, which is
  the safe value. Override it when concurrent events can only strengthen your
  invariant and shouldn't cause a conflict (the asymmetric DCB pattern).
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
