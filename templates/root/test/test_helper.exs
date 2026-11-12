# By default only the tests that pin down the board run: each write slice's
# board scenarios (`core_test.exs`) and its command's shape
# (`command_test.exs`), each read slice's scenarios, and the framework guards.
# Everything else — adapters, processors, utilities — carries
# `@moduletag :extra` and runs by hand with `mix test --include extra`.
# Screens, controllers and plugs get no tests.
ExUnit.start(exclude: [:extra])
