defmodule LoadTest.MixProject do
  use Mix.Project

  def project do
    [
      app: :load_test,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def releases do
    [
      load_test: [
        include_executables_for: [:unix],
        applications: [load_test: :permanent]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :gun],
      mod: {LoadTest.Application, []}
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.9"},
      {:prometheus_ex, "~> 5.0"},
      {:prometheus_plugs, "~> 1.0"},
      {:prometheus, "~> 5.0", override: true},
      {:parent, "~> 0.13"},
      {:uuid, "~> 1.1"},
      {:finch, "~> 0.23"},
      {:jose, "~> 1.11"},
      {:jiffy, "~> 2.0"},
      {:observer_cli, "~> 2.0"},
      {:gun, "~> 2.4"}
    ]
  end
end
