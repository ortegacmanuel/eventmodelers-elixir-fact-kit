defmodule MyApp.ScenarioTestsTest do
  use ExUnit.Case, async: true

  test "a slice's tests are its board scenarios: one describe each, nothing else" do
    offences =
      for file <- Path.wildcard(".build-kit/.slices/*/*/slice.json"),
          slice = Jason.decode!(File.read!(file)),
          dir = "test/my_app/slices/#{folder(slice["title"])}",
          File.dir?(dir),
          offence <- offences(dir, Enum.map(slice["specifications"] || [], & &1["title"])),
          do: "#{dir}: #{offence}"

    assert offences == [], Enum.join(offences, "\n")
  end

  defp offences(dir, scenarios) do
    files =
      for f <- Path.wildcard("#{dir}/*_test.exs"),
          not (File.read!(f) =~ ~r/@moduletag :extra/),
          do: Path.basename(f)

    core = Path.join(dir, "core_test.exs")
    source = if File.exists?(core), do: File.read!(core), else: ""
    describes = for [_, t] <- Regex.scan(~r/^  describe "((?:[^"\\]|\\.)*)"/m, source), do: t
    loose = Regex.scan(~r/^  test "/m, source)

    Enum.map(files -- ["core_test.exs"], &"#{&1} is not a scenario test") ++
      Enum.map(describes -- scenarios, &"describe not on the board: #{&1}") ++
      Enum.map(scenarios -- describes, &"scenario without its describe: #{&1}") ++
      if(loose == [], do: [], else: ["#{length(loose)} test(s) outside a describe"])
  end

  defp folder(title) do
    title
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end
end
