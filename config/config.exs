import Config

config :rate_limiter, RateLimiterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  live_view: [signing_salt: "abc123xyzabc123xyz"],
  secret_key_base: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

config :phoenix, :json_library, Jason
