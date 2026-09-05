defmodule MyApp.Reader do
  @moduledoc """
  Reads from the event store by picking the right index instead of walking the
  ledger.

  ## The problem it solves

  `Fact.read(db, {:query, %Fact.QueryItem{}})` turns the query into a function
  and **walks the entire ledger**, applying it event by event. It works, but
  it's O(n) on store size. Measured:

      tag query, store of    200 events →   1.3 ms
      tag query, store of 20,000 events → 235.0 ms
      the same, via the tag index       →   0.07 ms   (3,300×)

  FACT already maintains indices on disk (`indices/event_tags`,
  `indices/event_type`); they just aren't used unless you ask. This module picks
  the most selective one and filters in memory whatever the index can't express.

  It matters because **every write starts with a read**: `Decide` reads and folds
  before deciding, and reads again to wait for visibility. Without this, each
  saved command gets more expensive as history grows.

  ## How it picks

    * **With tags** → the first tag's index, then the remaining tags and the
      types are filtered in memory. This is the case for almost every slice, and
      the one that gains most: tags carry ids, so the index returns a handful of
      events instead of the whole store.
    * **Types only** → one index per type, merged and ordered by position. Here
      the gain isn't in finding but in **not reading other people's events**.
    * **Anything else** (`:all`, `:none`, `data` queries) → the original path.

  On `data` queries (`Fact.QueryItem.data/1`): **avoid them.** If the database
  was created without a data indexer their behaviour depends on store state —
  sometimes they return empty, sometimes they raise. Do your classification with
  tags, which are indexed. If you ever need them, create the database with the
  matching indexer and measure before relying on them.

  ## What doesn't change

  The result is **identical** to the scan: same events, same order by
  `store_position`, same fields. That isn't an aspiration — assert it in
  `test/my_app/reader_test.exs` by comparing both paths query by query. If they
  ever stop matching, the test says so.
  """

  @doc """
  Reads the events matching `query`, in `store_position` order.

  Accepts the same shapes as `Fact.read/2` in its `{:query, ...}` form: a
  `%Fact.QueryItem{}`, a list of them (a composite query, OR-ed), or `:all` /
  `:none`.
  """
  def read(db, query)

  def read(db, items) when is_list(items) do
    # Composite: each item is an alternative. Union them and sort by position so
    # the fold sees the same sequence a scan would.
    items
    |> Enum.flat_map(&read(db, &1))
    |> Enum.uniq_by(& &1["event_id"])
    |> Enum.sort_by(& &1["store_position"])
  end

  # `data` queries have no index: fall back to the original path.
  def read(db, %Fact.QueryItem{data: [_ | _]} = query), do: scan(db, query)

  def read(db, %Fact.QueryItem{tags: [tag | rest], types: types}) do
    db
    |> Fact.read({:index, {Fact.EventTagsIndexer, nil}, tag})
    |> Enum.filter(&matches?(&1, rest, types))
  end

  def read(db, %Fact.QueryItem{tags: [], types: [type]}) do
    db |> Fact.read({:index, {Fact.EventTypeIndexer, nil}, type}) |> Enum.to_list()
  end

  def read(db, %Fact.QueryItem{tags: [], types: [_ | _] = types}) do
    types
    |> Enum.flat_map(&Fact.read(db, {:index, {Fact.EventTypeIndexer, nil}, &1}))
    |> Enum.sort_by(& &1["store_position"])
  end

  def read(db, query), do: scan(db, query)

  defp scan(db, query), do: db |> Fact.read({:query, query}) |> Enum.to_list()

  # Tags inside a QueryItem combine with AND and types with OR. The index has
  # already resolved the first tag; the rest are applied here.
  defp matches?(event, tags, types) do
    type_ok?(event, types) and tags_ok?(event, tags)
  end

  defp type_ok?(_event, []), do: true
  defp type_ok?(event, types), do: event["event_type"] in types

  defp tags_ok?(_event, []), do: true

  defp tags_ok?(event, tags) do
    on_event = MapSet.new(event["event_tags"] || [])
    Enum.all?(tags, &MapSet.member?(on_event, &1))
  end
end
