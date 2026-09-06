import Config

if config_env() == :prod do
  # **Absolute, always.** A release starts with its cwd inside its own `bin/`,
  # so a relative path points somewhere else and the store fails quietly.
  config :my_app, :fact_path, System.get_env("FACT_PATH") || "/opt/my_app/data/fact_db"
end
