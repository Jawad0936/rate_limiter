defmodule RateLimiter.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RateLimiter.ETS,
      {Registry, keys: :unique, name: RateLimiter.Registry},
      RateLimiter.UserSupervisor,
      RateLimiterWeb.Endpoint,
    ]

    opts = [strategy: :one_for_one, name: RateLimiter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
