defmodule RateLimiterWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :rate_limiter

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: [store: :cookie, key: "_rate_limiter_key", signing_salt: "abc123xyz"]]]

  plug Plug.Static,
    at: "/",
    from: :rate_limiter,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug Plug.Session,
    store: :cookie,
    key: "_rate_limiter_key",
    signing_salt: "abc123xyz"

  plug RateLimiterWeb.Router
end
