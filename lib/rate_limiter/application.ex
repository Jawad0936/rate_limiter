defmodule RateLimiter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

   use Application
  @impl true
  def start(_type, _args) do
    children = [
      RateLimiter.ETS,
      {Registry, keys: :unique, name: RateLimiter.Registry},
      RateLimiter.UserSupervisor,
    ]

    opts = [strategy: :one_for_one, name: RateLimiter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
