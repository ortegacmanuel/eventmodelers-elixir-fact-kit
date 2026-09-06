defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {MyApp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # The event store: files, no database.
      {:fact, "~> 0.2.0"},
      # HTTP client for the external systems an automation slice calls.
      # Remove it if none do.
      {:req, "~> 0.5"},
      {:phoenix, "~> 1.8.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      # `lazy_html` is what `Phoenix.LiveViewTest` needs for `element/2` and
      # `has_element?/2`. Phoenix pulls it in for you.
      #
      # **The version is pinned, and it isn't superstition.** Since 0.1.x it
      # uses `cc_precompiler`: instead of building lexbor with cmake it
      # downloads a prebuilt NIF. That only helps if the download works — and
      # when it doesn't, the fallback is cmake, which plenty of machines don't
      # have. The failure arrives as "cmake: not found" during `mix deps.get`
      # on a fresh clone, which names the wrong culprit entirely.
      #
      # 0.1.11 has a working precompiled build. Bump it when you have a reason
      # to, not by habit.
      {:lazy_html, "0.1.11", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "fact.setup", "assets.setup", "assets.build"],
      # **`fact.setup` goes in all three.** Without the store created,
      # `MyApp.Application.fact_db/0` raises after two seconds and takes down
      # whatever the caller was doing — and the first time it bites is on
      # `mix phx.server`, where it looks like a LiveView crash.
      #
      # A release runs no aliases at all, so a deployment has to create the
      # store as its own explicit step. See README.
      test: ["fact.setup", "test"],
      "phx.server": ["fact.setup", "phx.server"],
      "fact.setup": &fact_setup/1,
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind my_app", "esbuild my_app"],
      "assets.deploy": [
        "tailwind my_app --minify",
        "esbuild my_app --minify",
        "phx.digest"
      ],
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
