import Config

# A separate store, so tests never mix with development data.
config :my_app, fact_path: "data/test/fact_db"

# Automation slices poll or subscribe. Left running during the suite they make
# real network calls, so every processor takes a `start?` option and it is
# switched off here.
#
#     config :my_app, :my_automation_slice, start?: false
