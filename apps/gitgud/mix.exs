defmodule GitGud.Mixfile do
  use Mix.Project

  def project do
    [app: :gitgud,
     version: "0.2.8",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.4",
     elixirc_paths: elixirc_paths(Mix.env),
     start_permanent: Mix.env == :prod,
     aliases: aliases(),
     deps: deps()]
  end

  def application do
    [mod: {GitGud.Application, []},
     extra_applications: [:logger, :runtime_tools, :ssh]]
  end

  #
  # Helpers
  #

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  defp deps do
    [{:ecto, "~> 3.1"},
     {:ecto_sql, "~> 3.1"},
     {:postgrex, "~> 0.14"},
     {:phoenix, "~> 1.4", optional: true},
     {:phoenix_pubsub, "~> 1.1", optional: true},
     {:jason, "~> 1.1"},
     {:argon2_elixir, "~> 2.0"},
     {:plug, "~> 1.8", optional: true},
     {:plug_cowboy, "~> 2.1", only: :test},
     {:faker, "~> 0.12", only: :test},
     {:gitrekt, in_umbrella: true}]
  end

  defp aliases do
    ["ecto.setup": ["ecto.create", "ecto.migrate", "run priv/db/seeds.exs"],
     "ecto.reset": ["ecto.drop", "ecto.setup"],
     test: ["ecto.create --quiet", "ecto.migrate", "test"]]
  end
end
