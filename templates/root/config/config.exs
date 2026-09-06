import Config

# The store lives on files, so its path is the only thing worth configuring.
# Each environment overrides it below; production does it in `runtime.exs`,
# where the value comes from the environment.
config :my_app, fact_path: "data/fact_db"

import_config "#{config_env()}.exs"
