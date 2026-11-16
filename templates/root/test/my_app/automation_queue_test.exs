defmodule MyApp.AutomationQueueTest do
  use ExUnit.Case, async: true

  # The board's READMODEL → AUTOMATION edge, checked in code. A processor reads
  # its TODO queue through `<Queue>.Context.pending/0`, and holds the queue as a
  # value so it compiles before the queue slice is built — which also means the
  # compiler no longer checks the call. This does, once both slices exist.

  test "every automation's TODO queue exposes pending/0" do
    offences =
      for file <- Path.wildcard("lib/my_app/slices/*/processor.ex"),
          [_, queue] <- Regex.scan(~r/alias (MyApp\.Slices\.\w+\.Context), as: Queue\b/, File.read!(file)),
          module = Module.concat([queue]),
          # Not built yet: the automation was built first, against the name.
          Code.ensure_loaded?(module),
          not function_exported?(module, :pending, 0),
          do: "#{file}: #{queue}.pending/0 is missing"

    assert offences == [], Enum.join(offences, "\n")
  end
end
