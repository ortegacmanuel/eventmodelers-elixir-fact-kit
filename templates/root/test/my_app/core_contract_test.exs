defmodule MyApp.CoreContractTest do
  use ExUnit.Case, async: true

  @contract ~w(query append_condition initial_state apply_event execute next_query project)

  test "a slice's core.ex defines only the contract's functions" do
    offences =
      for file <- Path.wildcard("lib/my_app/slices/*/core.ex"),
          [_, name] <- Regex.scan(~r/^\s*defp?\s+([a-z_][a-zA-Z0-9_?!]*)/m, File.read!(file)),
          name not in @contract,
          uniq: true,
          do: "#{file}: #{name}"

    assert offences == [], Enum.join(offences, "\n")
  end
end
