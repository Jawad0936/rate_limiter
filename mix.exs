defmodule RateLimiter.MixProject do
  use Mix.Project

  def project do
    [
      app: :rate_limiter,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
    # Phoenix for Plug + LiveView dashboard
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_html, "~> 4.0"},

    # Telemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_poller, "~> 1.0"},

    # Property-based testing
    {:stream_data, "~> 0.6", only: :test},

    # Dev/test helpers
    {:phoenix_live_reload, "~> 1.4", only: :dev},
    {:esbuild, "~> 0.8", only: :dev},
  ]
  end
end
