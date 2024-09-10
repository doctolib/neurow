defmodule Neurow.MixProject do
  use Mix.Project

  def project do
    [
      app: :neurow,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_paths: [
        "test",
        "integration_test"
      ],
      aliases: [
        "test.unit": "test test",
        "test.integration": "test --no-start integration_test"
      ]
    ]
  end

  def cli do
    [preferred_envs: ["test.unit": :test, "test.integration": :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Neurow.Application, []}
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:libcluster, "~> 3.0"},
      {:libcluster_ec2, "~> 0.5"},
      {:prometheus_ex, "~> 3.1"},
      {:prometheus_plugs, "~> 1.0"},
      {:jose, "~> 1.11"},
      {:jiffy, "~> 1.1"},
      {:httpoison, "~> 2.0", only: [:test]}
    ]
  end
end
