defmodule RateLimiter.SlidingWindow do
  @moduledoc """
  A GenServer implementing the Sliding Window rate limiting algorithm.

  ## Algorithm

  For each user, we maintain a list of monotonic timestamps — one per
  allowed request. On every `allow?/1` call:

    1. Drop all timestamps older than `now - window_ms`
    2. Count remaining timestamps
    3. If count >= limit → deny, return `retry_after_ms` (oldest entry + window - now)
    4. If count < limit  → append now, allow the request
    5. Write updated state to ETS for dashboard reads

  ## Comparison with Token Bucket

  | Property           | Token Bucket         | Sliding Window          |
  |--------------------|----------------------|-------------------------|
  | Burst behaviour    | Allows up to capacity | Strictly bounded        |
  | Memory per user    | O(1)                 | O(requests in window)   |
  | Fairness           | Can reset and burst  | Smooth, no gaming       |
  | Retry precision    | Estimated from rate  | Exact: oldest_ts + window - now |

  ## Memory consideration

  At 100 req/sec over a 60s window, each user holds up to 6000 timestamps.
  Each Erlang integer is ~8 bytes → ~48KB per user at max rate.
  Acceptable for a portfolio/production service. If memory were critical,
  a sliding window counter (fixed sub-buckets) trades precision for O(1) memory.

  ## Why a list and not a queue?

  Erlang lists are prepend-O(1). We always prepend new timestamps and drop
  from the tail. Pruning is a single `Enum.drop_while/2` — O(k) where k is
  the number of expired entries, not the total list length.
  """

  use GenServer
  require Logger

  alias RateLimiter.ETS

  @type config :: %{
    limit: pos_integer(),
    window_ms: pos_integer()
  }

  @type window_state :: %{
    timestamps: [integer()],  # monotonic ms, newest first
    limit: pos_integer(),
    window_ms: pos_integer()
  }

  @default_config %{
    limit: 100,       # max requests
    window_ms: 60_000 # per 60 seconds
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    config   = Keyword.get(opts, :config, @default_config)

    GenServer.start_link(
      __MODULE__,
      %{user_id: user_id, config: config},
      name: via(user_id)
    )
  end

  @doc """
  Check whether a request from `user_id` is allowed.

  Returns `{:allow, requests_remaining}` or `{:deny, retry_after_ms}`.
  """
  @spec allow?(String.t()) :: {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def allow?(user_id) do
    case GenServer.whereis(via(user_id)) do
      nil  -> {:deny, 0}
      _pid -> GenServer.call(via(user_id), :allow?)
    end
  end

  @doc "Peek at current window state. Reads from ETS — no GenServer hop."
  @spec state(String.t()) :: {:ok, window_state()} | :not_found
  def state(user_id) do
    case ETS.get({user_id, :sliding_window}) do
      {:ok, state} -> {:ok, state}
      :miss        -> :not_found
    end
  end

  def via(user_id) do
    {:via, Registry, {RateLimiter.Registry, {__MODULE__, user_id}}}
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{user_id: user_id, config: config}) do
    state = %{
      timestamps: [],
      limit:      config.limit,
      window_ms:  config.window_ms
    }

    ETS.put({user_id, :sliding_window}, state)

    Logger.debug("[SlidingWindow] Started for #{user_id} — limit=#{config.limit} window=#{config.window_ms}ms")

    {:ok, %{user_id: user_id, window: state}}
  end

  @impl true
  def handle_call(:allow?, _from, %{user_id: user_id, window: window} = state) do
    now    = now_ms()
    window = prune(window, now)

    count  = length(window.timestamps)

    {reply, updated_window} =
      if count < window.limit do
        new_window = %{window | timestamps: [now | window.timestamps]}
        remaining  = window.limit - count - 1
        {{:allow, remaining}, new_window}
      else
        retry_after = retry_after_ms(window, now)
        {{:deny, retry_after}, window}
      end

    ETS.put({user_id, :sliding_window}, updated_window)
    emit_telemetry(user_id, reply, updated_window)

    {:reply, reply, %{state | window: updated_window}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Drop timestamps older than the window. Timestamps are newest-first,
  # so expired ones are always at the tail — drop_while from the reversed end.
  defp prune(%{timestamps: timestamps, window_ms: window_ms} = window, now) do
    cutoff     = now - window_ms
    pruned = Enum.filter(timestamps, fn ts -> ts > cutoff end)
    %{window | timestamps: pruned}
  end

  # How long until the oldest request falls outside the window?
  defp retry_after_ms(%{timestamps: timestamps, window_ms: window_ms}, now) do
    oldest = List.last(timestamps)  # oldest is at the tail (smallest value)
    max(0, oldest + window_ms - now)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp emit_telemetry(user_id, reply, window) do
    event = case reply do
      {:allow, _} -> [:rate_limiter, :sliding_window, :allowed]
      {:deny, _}  -> [:rate_limiter, :sliding_window, :denied]
    end

    :telemetry.execute(event, %{count: length(window.timestamps)}, %{user_id: user_id})
  end
end
