defmodule RateLimiter.MixProject do
  use Mix.Project

  def project do
    [
      app: :rate_limiter,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      config_path: "config/config.exs"

    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RateLimiter.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_html, "~> 4.0"},
    {:phoenix_live_reload, "~> 1.4", only: :dev},
    {:jason, "~> 1.4"},
    {:bandit, "~> 1.0"},
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_poller, "~> 1.0"},
    {:plug_cowboy, "~> 2.7"},
    {:stream_data, "~> 0.6", only: :test},
  ]
  end
end
