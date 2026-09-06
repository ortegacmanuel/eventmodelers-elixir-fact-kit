defmodule MyApp.MixProject do
  use Mix.Project

  # Plain Elixir, no Phoenix. The kit builds **domain** slices, and the
  # framework under `lib/my_app/` is pure domain — it depends on nothing but
  # `Logger` and `fact`. Phoenix is your call later, for screens, which this kit
  # deliberately does not build.
  #
  # Installing into an existing Phoenix project? Don't take this file. Read
  # INSTALL.md: it says which three things to merge into the `mix.exs` you
  # already have.
  def project do
    [
      app: :my_app,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Without this, `mix precommit` runs its `test` step in the dev environment and
  # Mix refuses. Found by actually running it on a fresh install.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MyApp.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # The event store: files, no database.
      {:fact, "~> 0.2.0"},
      # Slices that call an external system use `Req`. Drop it if none do.
      {:req, "~> 0.5"}
    ]
  end

  # **`fact.setup` goes in `setup` and in `test`, and in `phx.server` too if you
  # add Phoenix.** Without the store created, `MyApp.Application.fact_db/0`
  # raises after two seconds and takes down whatever the caller was doing. A
  # release runs no aliases at all, so a deployment has to create the store as
  # its own step — see README.
  defp aliases do
    [
      setup: ["deps.get", "fact.setup"],
      test: ["fact.setup", "test"],
      "fact.setup": &fact_setup/1,
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp fact_setup(_) do
    fact_path = Application.get_env(:my_app, :fact_path, "data/fact_db")

    unless File.exists?(Path.join(fact_path, ".bootstrap")) do
      Mix.Task.run("fact.create", ["--path", fact_path, "--name", "fact_db"])
    end
  end
end
