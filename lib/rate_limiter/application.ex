defmodule RateLimiter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

   use Application

  @impl true
  def start(_type, _args) do
    children = [
      # ETS owner must start first — everything else depends on the table existing
      RateLimiter.ETS,
    ]

    opts = [strategy: :one_for_one, name: RateLimiter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
