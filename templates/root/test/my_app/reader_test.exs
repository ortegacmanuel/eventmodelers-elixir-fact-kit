defmodule MyApp.ReaderTest do
  # A framework guard. `MyApp.Reader.selects?/2` is the in-memory match that
  # `MyApp.Reader` finishes its index reads with and that `MyApp.Scenario` uses
  # as the scenarios' store. Here it is held against FACT's own scan: the same
  # events, the same queries, the same answer. And `read/2` — the index path —
  # must return what the scan returns.
  use ExUnit.Case, async: true

  import Fact.QueryItem

  test "selects?/2 and read/2 agree with FACT's scan" do
    db = MyApp.Application.fact_db()
    run = "run#{System.unique_integer([:positive])}"

    events = [
      %{type: "#{run}A", data: %{}, tags: ["#{run}:1", "#{run}x:1"]},
      %{type: "#{run}A", data: %{}, tags: ["#{run}:2"]},
      %{type: "#{run}B", data: %{}, tags: ["#{run}:1"]},
      %{type: "#{run}C", data: %{}, tags: ["#{run}:2", "#{run}x:1"]}
    ]

    {:ok, _} = Fact.append(db, events)
    # Both indices (tags and types) have to have caught up before comparing.
    await(db, types(["#{run}A", "#{run}B", "#{run}C"]), 4)
    mine = await(db, join([tags(["#{run}:1"]), tags(["#{run}:2"])]), 4)

    queries = [
      types(["#{run}A"]),
      types(["#{run}A", "#{run}B"]),
      tags(["#{run}:1"]),
      tags(["#{run}:1", "#{run}x:1"]),
      types(["#{run}A", "#{run}C"]) |> tags(["#{run}x:1"]),
      join([types(["#{run}B"]), tags(["#{run}:2"])]),
      :none
    ]

    ids = MapSet.new(mine, & &1["event_id"])

    for query <- queries do
      scan = db |> Fact.read({:query, query}) |> Enum.filter(&(&1["event_id"] in ids))
      by_index = db |> MyApp.Reader.read(query) |> Enum.filter(&(&1["event_id"] in ids))
      in_memory = Enum.filter(mine, &MyApp.Reader.selects?(query, &1))

      expected = Enum.map(scan, & &1["event_id"]) |> Enum.sort()
      assert Enum.map(in_memory, & &1["event_id"]) |> Enum.sort() == expected, inspect(query)
      assert Enum.map(by_index, & &1["event_id"]) |> Enum.sort() == expected, inspect(query)
    end
  end

  # FACT indexes a few milliseconds after the append returns.
  defp await(db, query, count, attempts \\ 200) do
    found = db |> Fact.read({:query, query}) |> Enum.to_list()

    cond do
      length(found) >= count -> found
      attempts == 0 -> flunk("the appended events never became readable")
      true -> Process.sleep(5) && await(db, query, count, attempts - 1)
    end
  end
end
