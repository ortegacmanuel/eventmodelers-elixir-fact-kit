import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zYFBMVcWUJDE2tVxuQ97cZl7o4LinyAF5aU1NiqUOwQfhPs2aMj2YNgdIIvCFmkg",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# A separate store, so tests never mix with development data.
config :my_app, fact_path: "data/test/fact_db"

# Automation slices poll or subscribe. Left running during the suite they make
# real network calls, so every processor takes a `start?` option and it is
# switched off here:
#
#     config :my_app, :my_automation_slice, start?: false
