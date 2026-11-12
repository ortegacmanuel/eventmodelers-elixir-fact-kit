defmodule MyApp.SliceIsolationTest do
  use ExUnit.Case, async: true

  @framework ~w(Application TaskSupervisor Decide Reader Command Event StateChange StateView)

  # The project's declared domain modules: shared knowledge that folds no
  # events (a catalogue, a calendar rule). Empty until the project decides one.
  @domain ~w()

  test "a slice names only itself, the framework and the declared domain modules" do
    offences =
      for file <- Path.wildcard("lib/my_app/slices/*/*.ex"),
          own = slice_module(file),
          ref <- references(File.read!(file)),
          not allowed?(ref, own, Path.basename(file)),
          uniq: true,
          do: "#{file}: #{ref}"

    assert offences == [], Enum.join(offences, "\n")
  end

  test "a declared domain module is pure and folds no events" do
    offences =
      for name <- @domain,
          file = "lib/my_app/#{Macro.underscore(name)}.ex",
          {pattern, what} <- [
            {~r/\bFact\.|MyApp\.Reader|MyApp\.Decide/, "reads the store"},
            {~r/\bapply_event\b|"event_type"/, "folds events"},
            {~r/utc_now|utc_today/, "reads the clock"}
          ],
          File.read!(file) =~ pattern,
          do: "#{file}: #{what}"

    assert offences == [], Enum.join(offences, "\n")
  end

  defp allowed?("MyApp.Slices." <> rest, own, file) do
    case String.split(rest, ".") do
      [^own | _] -> true
      [_other, "Context"] -> file == "processor.ex"
      _ -> false
    end
  end

  defp allowed?("MyApp." <> rest, _own, _file),
    do: hd(String.split(rest, ".")) in @framework or rest in @domain

  defp references(source) do
    braces =
      for [_, base, names] <- Regex.scan(~r/alias\s+(MyApp\.[\w.]+)\.\{([^}]*)\}/, source),
          name <- String.split(names, ","),
          do: base <> "." <> String.trim(name)

    plain =
      for [ref] <- Regex.scan(~r/(?>MyApp\.[A-Z]\w*(?:\.[A-Z]\w*)*)(?!\.\{)/, source),
          do: ref

    Enum.uniq(braces ++ plain)
  end

  defp slice_module(file),
    do: file |> Path.dirname() |> Path.basename() |> Macro.camelize()
end
