defmodule RateLimiter.TokenBucket do
  @moduledoc """
  A GenServer implementing the Token Bucket rate limiting algorithm.

  ## Algorithm

  Each user gets a bucket with:
    - `capacity`     — maximum tokens (burst ceiling)
    - `tokens`       — current token count (float, for sub-second refill accuracy)
    - `refill_rate`  — tokens added per millisecond
    - `last_refill`  — monotonic timestamp of last refill calculation

  On every `allow?/1` call:
    1. Calculate elapsed ms since last refill
    2. Add `elapsed * refill_rate` tokens (capped at capacity)
    3. If tokens >= 1: consume 1, allow the request
    4. If tokens < 1: reject the request
    5. Write new state to ETS for concurrent dashboard reads

  ## Why float tokens?

  If refill_rate is 0.01 tokens/ms (= 10 tokens/sec) and 50ms have elapsed,
  we've accumulated 0.5 tokens. Integer math would lose this. Floats let us
  accumulate fractional tokens between requests, which gives smooth refill
  behavior at high request rates.

  ## No background timer

  Refill is computed lazily on each request. This means:
  - Zero overhead when a user is idle
  - No timer drift or race between timer and request
  - Identical behavior whether requests arrive in bursts or steady stream
  """

  use GenServer
  require Logger

  alias RateLimiter.ETS

  @type config :: %{
    capacity: pos_integer(),
    refill_rate_per_sec: pos_integer()
  }

  @type bucket :: %{
    tokens: float(),
    capacity: pos_integer(),
    refill_rate: float(),   # tokens per millisecond
    last_refill: integer()  # monotonic ms
  }

  # Default config — 100 requests/sec, burst up to 200
  @default_config %{
    capacity: 200,
    refill_rate_per_sec: 100
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start a TokenBucket GenServer for a specific user.
  Called by UserSupervisor — not directly.
  """
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

  Returns `{:allow, tokens_remaining}` or `{:deny, retry_after_ms}`.

  This call goes to the user's GenServer — serialized, no race conditions.
  The GenServer then writes updated state to ETS.
  """
  @spec allow?(String.t()) :: {:allow, float()} | {:deny, non_neg_integer()}
  def allow?(user_id) do
    case GenServer.whereis(via(user_id)) do
      nil ->
        # Process not started yet — caller (Plug) will start it via UserSupervisor
        {:deny, 0}

      _pid ->
        GenServer.call(via(user_id), :allow?)
    end
  end

  @doc "Peek at the current bucket state without consuming a token. Used by dashboard."
  @spec state(String.t()) :: {:ok, bucket()} | :not_found
  def state(user_id) do
    case ETS.get({user_id, :token_bucket}) do
      {:ok, bucket} -> {:ok, bucket}
      :miss         -> :not_found
    end
  end

  @doc "Expose the via tuple for UserSupervisor to use."
  def via(user_id) do
    {:via, Registry, {RateLimiter.Registry, {__MODULE__, user_id}}}
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{user_id: user_id, config: config}) do
    bucket = %{
      tokens:      config.capacity * 1.0,  # start full
      capacity:    config.capacity,
      refill_rate: config.refill_rate_per_sec / 1000.0,  # convert to per-ms
      last_refill: now_ms()
    }

    # Write initial state to ETS so dashboard can see it immediately
    ETS.put({user_id, :token_bucket}, bucket)

    Logger.debug("[TokenBucket] Started for #{user_id} — capacity=#{config.capacity} rate=#{config.refill_rate_per_sec}/sec")

    {:ok, %{user_id: user_id, bucket: bucket}}
  end

  @impl true
  def handle_call(:allow?, _from, %{user_id: user_id, bucket: bucket} = state) do
    now    = now_ms()
    bucket = refill(bucket, now)

    {reply, updated_bucket} =
      if bucket.tokens >= 1.0 do
        new_bucket = %{bucket | tokens: bucket.tokens - 1.0}
        {{:allow, new_bucket.tokens}, new_bucket}
      else
        retry_after = retry_after_ms(bucket)
        {{:deny, retry_after}, bucket}
      end

    # Write to ETS — concurrent reads from dashboard will see this immediately
    ETS.put({user_id, :token_bucket}, updated_bucket)

    emit_telemetry(user_id, reply, updated_bucket)

    {:reply, reply, %{state | bucket: updated_bucket}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Add tokens for elapsed time, cap at capacity.
  defp refill(%{tokens: tokens, refill_rate: rate, capacity: cap, last_refill: last} = bucket, now) do
    elapsed      = now - last
    new_tokens   = min(tokens + elapsed * rate, cap * 1.0)
    %{bucket | tokens: new_tokens, last_refill: now}
  end

  # How long until 1 token is available?
  defp retry_after_ms(%{tokens: tokens, refill_rate: rate}) do
    deficit = 1.0 - tokens
    ceil(deficit / rate)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp emit_telemetry(user_id, reply, bucket) do
    event = case reply do
      {:allow, _} -> [:rate_limiter, :token_bucket, :allowed]
      {:deny, _}  -> [:rate_limiter, :token_bucket, :denied]
    end

    :telemetry.execute(event, %{tokens: bucket.tokens}, %{user_id: user_id})
  end
end
