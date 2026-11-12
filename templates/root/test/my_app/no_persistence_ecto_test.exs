defmodule MyApp.NoPersistenceEctoTest do
  @moduledoc """
  Ecto is here for one thing: commands as `embedded_schema` + `Ecto.Changeset`.
  The store is `fact` and read models are folded, so nothing under `lib/` may
  define a Repo, a persisted schema or a migration. An agent reaching for them
  is drifting towards a database this app doesn't have.
  """

  use ExUnit.Case, async: true

  @forbidden [
    {~r/\buse Ecto\.Repo\b/, "an Ecto.Repo"},
    {~r/^\s*schema\s+"/m, "a persisted schema (`schema \"...\"`); use `embedded_schema`"},
    {~r/\buse Ecto\.Migration\b/, "a migration"}
  ]

  test "lib/ has no Repo, no persisted schema and no migration" do
    offences =
      for file <- Path.wildcard("lib/**/*.ex"),
          {pattern, what} <- @forbidden,
          File.read!(file) =~ pattern,
          do: "#{file}: #{what}"

    assert offences == [], Enum.join(offences, "\n")
  end
end
