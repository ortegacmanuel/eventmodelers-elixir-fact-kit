defmodule MyApp.EventSpecTest do
  use ExUnit.Case, async: true

  test "every event's type and tags match its slice.json" do
    board = board_events()

    offences =
      for impl <- impls(),
          %{type: type, tags: tags} = impl.spec(),
          expected = Map.get(board, type),
          expected != MapSet.new(tags),
          do:
            "#{type}: tags #{inspect(Enum.sort(tags))}, the board says #{inspect(Enum.sort(expected))}"

    unknown = for impl <- impls(), not Map.has_key?(board, impl.spec().type), do: impl.spec().type

    assert offences == [], Enum.join(offences, "\n")

    assert board == %{} or unknown == [],
           "types not on the board (renamed or invented): #{Enum.join(unknown, ", ")}"
  end

  defp impls do
    structs =
      case MyApp.Event.__protocol__(:impls) do
        {:consolidated, structs} -> structs
        :not_consolidated -> Protocol.extract_impls(MyApp.Event, [Mix.Project.compile_path()])
      end

    for s <- structs, s != Any, do: Module.concat(MyApp.Event, s)
  end

  defp board_events do
    for file <- Path.wildcard(".build-kit/.slices/**/slice.json"),
        event <- Jason.decode!(File.read!(file))["events"] || [],
        reduce: %{} do
      acc -> Map.put(acc, event["title"], tag_names(event["fields"] || []))
    end
  end

  defp tag_names(fields) do
    for field <- fields,
        f <- [field | field["subfields"] || []],
        f["idAttribute"] == true or f["tag"] == true,
        into: MapSet.new(),
        do: f["name"] |> String.replace_suffix("Id", "") |> Macro.underscore()
  end
end
