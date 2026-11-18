defmodule MyApp.ContextApiTest do
  use ExUnit.Case, async: true

  # A slice's Context exposes its role's function, always with the same name,
  # so a screen, a controller or an automation can call it before the slice is
  # built: a write slice `execute/1`, a read slice `read/0` or `read/1`, a TODO
  # queue `pending/0`. The role comes from the files: `decider.ex` is a write
  # slice, `read_model.ex` a read slice.

  test "every slice's Context exposes its role's function" do
    offences =
      for dir <- Path.wildcard("lib/my_app/slices/*"),
          File.exists?(Path.join(dir, "context.ex")),
          source = File.read!(Path.join(dir, "context.ex")),
          offence <- offences(dir, source),
          do: "#{dir}/context.ex: #{offence}"

    assert offences == [], Enum.join(offences, "\n")
  end

  defp offences(dir, source) do
    cond do
      File.exists?(Path.join(dir, "decider.ex")) and not defines?(source, "execute") ->
        ["a write slice exposes execute/1"]

      File.exists?(Path.join(dir, "read_model.ex")) and
          not (defines?(source, "read") or defines?(source, "pending")) ->
        ["a read slice exposes read/0 or read/1 (a TODO queue, pending/0)"]

      true ->
        []
    end
  end

  defp defines?(source, name), do: source =~ ~r/^\s*def #{name}\b/m
end
