# ─────────────────────────────────────────────────────────────────────────────
#  Trozos para los `config/*.exs` que genera `mix phx.new`. Bórralo después.
# ─────────────────────────────────────────────────────────────────────────────

#  config/dev.exs
config :my_app, fact_path: "data/fact_db"

#  config/test.exs — store aparte, para no mezclar con el de desarrollo.
config :my_app, fact_path: "data/test/fact_db"

#  config/runtime.exs, dentro del bloque de producción
config :my_app, :fact_path, System.get_env("FACT_PATH") || "/opt/my_app/data/fact_db"

#  Y en `mix.exs`, la tarea que crea el store si no existe. Va en los alias de
#  `test`, `setup` y `phx.server`: sin ella `fact_db/0` lanza tras dos segundos.
#
#  defp fact_setup(_) do
#    fact_path = Application.get_env(:my_app, :fact_path, "data/fact_db")
#
#    unless File.exists?(Path.join(fact_path, ".bootstrap")) do
#      Mix.Task.run("fact.create", ["--path", fact_path, "--name", "fact_db"])
#    end
#  end
