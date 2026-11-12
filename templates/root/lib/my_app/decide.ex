defmodule MyApp.Decide do
  @moduledoc """
  The engine behind every write: read → fold → decide → append, with DCB and
  optimistic concurrency.

  On a concurrency conflict it repeats the whole cycle (re-read, re-fold,
  re-decide, re-append).

  ## Reading what you just wrote

  `Fact.append/3` confirms the append a few milliseconds before the event is
  visible to a subsequent read (measured: 7–10 ms). If your app is LiveView and
  a handler writes and then **immediately** re-reads to repaint, without a wait
  the user clicks and the page still shows the old state.

  So `execute/4` doesn't return until the event it just wrote is visible to a
  read. The wait lives here, in the one place every write passes through, rather
  than being scattered across handlers. It costs a few milliseconds per command,
  and in exchange everything above can assume what it wrote is there.

  ## Where the append condition is anchored, and its ceiling

  The append is conditional: "fail if any event matching this query appeared
  **after position P**". Today `P` is the position of the last folded event,
  which is **0** when there's nothing to fold — and for a brand-new entity that
  is the normal case, because nobody has written about it before.

  With `P = 0`, FACT scans the **entire** ledger applying the query, inside the
  `handle_call` of the single writing process. It's linear in accumulated
  history. Measured:

      ledger of     531 events → decide  29 ms
      ledger of   7,591 events → decide 256 ms
      ledger of  37,651 events → decide  1.1 s
      ledger of 157,711 events → decide  4.5 s

  **It isn't solved here on purpose**, because most systems never reach those
  numbers. When it starts to hurt, **the seam is `read_and_fold/3`**: have it
  return `max(visibility_mark, last)` instead of `last`, where the mark is the
  position up to which every FACT index has caught up (FACT announces it over
  PubSub as `{:indexed, position}`).

  Ask for the mark **before** reading, not after: that way everything the read
  can return sits below it, and the condition still watches from the mark
  onwards — which is where a concurrent writer would be. With that, the same
  decision over 157,711 events drops from 4.5 s to 8 ms.

  And the anchor can't be the head of the ledger: `MyApp.Reader` reads **by
  index**, and FACT's indices are maintained asynchronously. Anchoring at the
  head would be claiming to have seen events the index hadn't published yet.
  """

  require Logger

  @max_retries 3

  # Bound on the visibility wait. The measured delay is around 10 ms; 2 s is a
  # deliberately absurd margin, so it only ever runs out if something is badly
  # wrong.
  @visibility_attempts 400
  @visibility_wait_ms 5

  def execute(db, core, cmd, opts \\ []) do
    extra_tags = Keyword.get(opts, :extra_tags, [])
    retries = Keyword.get(opts, :retries, @max_retries)

    do_execute(db, core, cmd, extra_tags, retries)
  end

  defp do_execute(db, core, cmd, extra_tags, retries) do
    {state, last_position, follow_ups} = read_and_fold(db, core, cmd)

    case core.execute(cmd, state) do
      {:ok, events} ->
        fact_events =
          events
          |> Enum.map(&MyApp.Event.to_event/1)
          |> append_extra_tags(extra_tags)

        condition =
          {Fact.QueryItem.join(List.wrap(core.append_condition(cmd)) ++ follow_ups),
           last_position}

        case Fact.append(db, fact_events, condition) do
          {:ok, position} ->
            await_visibility(db, fact_events, position)
            {:ok, events}

          {:error, %Fact.ConcurrencyError{}} when retries > 0 ->
            Logger.debug("concurrency conflict, retrying (#{retries} left)")
            do_execute(db, core, cmd, extra_tags, retries - 1)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Waits until the freshly appended events show up in a read.
  #
  # The query is built from the events themselves — their type and their tags —
  # and not from `core.query/1`: some slices' decision query doesn't include the
  # type they emit (a slice that reads `NewsDrafted` and writes `NewsEdited`),
  # and waiting on that query would never see what was written. Since tags
  # always carry a unique id, the query returns a handful of events and the wait
  # is cheap.
  defp await_visibility(db, fact_events, position) do
    query =
      fact_events
      |> Enum.map(fn e -> Fact.QueryItem.types([e.type]) |> Fact.QueryItem.tags(e.tags) end)
      |> Fact.QueryItem.join()

    await(db, query, position, @visibility_attempts)
  end

  defp await(_db, _query, position, 0) do
    Logger.warning("the event at position #{position} did not become visible in time")
    :timeout
  end

  defp await(db, query, position, attempts) do
    visible =
      db
      |> MyApp.Reader.read(query)
      |> Enum.reduce(0, fn event, highest -> max(event["store_position"] || 0, highest) end)

    if visible >= position do
      :ok
    else
      Process.sleep(@visibility_wait_ms)
      await(db, query, position, attempts - 1)
    end
  end

  # Returns the folded state, the anchor for the append condition and the
  # follow-up queries read through `next_query/1`, which join the condition: a
  # decision is invalidated by a change to anything it read.
  # See the moduledoc: today the anchor is the last folded event's position, and
  # this is where you raise it to the visibility mark once the ledger grows.
  defp read_and_fold(db, core, cmd) do
    Code.ensure_loaded!(core)
    first = List.wrap(core.query(cmd))
    {state, last, read} = follow(db, core, MyApp.Reader.read(db, first), MapSet.new(first))
    {state, last, Enum.reject(MapSet.to_list(read), &(&1 in first))}
  end

  defp follow(db, core, events, read) do
    {state, last} =
      Enum.reduce(events, {core.initial_state(), 0}, fn event, {state, _pos} ->
        {core.apply_event(state, event), event["store_position"] || 0}
      end)

    new =
      if function_exported?(core, :next_query, 1),
        do: state |> core.next_query() |> List.wrap() |> Enum.reject(&MapSet.member?(read, &1)),
        else: []

    case new do
      [] ->
        {state, last, read}

      items ->
        events =
          (events ++ MyApp.Reader.read(db, items))
          |> Enum.uniq_by(& &1["event_id"])
          |> Enum.sort_by(& &1["store_position"])

        follow(db, core, events, MapSet.union(read, MapSet.new(items)))
    end
  end

  defp append_extra_tags(fact_events, []), do: fact_events

  defp append_extra_tags(fact_events, extra_tags) do
    Enum.map(fact_events, fn event ->
      Map.update(event, :tags, extra_tags, &(&1 ++ extra_tags))
    end)
  end
end
