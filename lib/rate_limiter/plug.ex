# lib/rate_limiter/plug.ex

defmodule RateLimiter.Plug do
  @behaviour Plug

  import Plug.Conn

  alias RateLimiter.{UserSupervisor, TokenBucket, SlidingWindow}

  @default_opts [
    algorithm: :token_bucket,
    identify_by: :auto,
    token_bucket: %{capacity: 100, refill_rate_per_sec: 10},
    sliding_window: %{limit: 100, window_ms: 60_000}
  ]

  @impl Plug
  def init(opts) do
    Keyword.merge(@default_opts, opts)
  end

  @impl Plug
  def call(conn, opts) do
    user_id   = identify(conn, opts[:identify_by])
    algorithm = opts[:algorithm]

    supervisor_opts =
      case algorithm do
        :token_bucket   -> [token_bucket: opts[:token_bucket]]
        :sliding_window -> [sliding_window: opts[:sliding_window]]
      end

    UserSupervisor.ensure_started(user_id, supervisor_opts)

    case check(algorithm, user_id) do
      {:allow, remaining} ->
        conn
        |> put_resp_header("x-ratelimit-limit", limit_for(algorithm, opts))
        |> put_resp_header("x-ratelimit-remaining", to_string(floor(remaining)))
        |> put_resp_header("x-ratelimit-algorithm", to_string(algorithm))

      {:deny, retry_after_ms} ->
        retry_after_sec = max(1, ceil(retry_after_ms / 1000))

        conn
        |> put_resp_header("retry-after", to_string(retry_after_sec))
        |> put_resp_header("x-ratelimit-algorithm", to_string(algorithm))
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{
            error: "rate_limit_exceeded",
            algorithm: algorithm,
            retry_after: retry_after_sec,
            user_id: user_id
          })
        )
        |> halt()
    end
  end

  defp identify(conn, :auto) do
    case get_in(conn.assigns, [:current_user, :id]) do
      nil -> identify(conn, :ip)
      id  -> "user:#{id}"
    end
  end

  defp identify(conn, :ip) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
    |> then(&"ip:#{&1}")
  end

  defp identify(conn, :user_id) do
    case get_in(conn.assigns, [:current_user, :id]) do
      nil -> identify(conn, :ip)
      id  -> "user:#{id}"
    end
  end

  defp check(:token_bucket, user_id),   do: TokenBucket.allow?(user_id)
  defp check(:sliding_window, user_id), do: SlidingWindow.allow?(user_id)

  defp limit_for(:token_bucket, opts),   do: to_string(opts[:token_bucket][:capacity] || 100)
  defp limit_for(:sliding_window, opts), do: to_string(opts[:sliding_window][:limit] || 100)
end
