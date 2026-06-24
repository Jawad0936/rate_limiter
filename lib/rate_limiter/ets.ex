defmodule RateLimiter.ETS do
  @moduledoc """
  Owns the shared ETS table used by all rate limiter GenServers.

  ## Why a single shared table?

  Each user's GenServer writes to ETS but does NOT own the table.
  This means:
  - The table survives individual GenServer crashes (fresh bucket on restart is acceptable)
  - Reads are fully concurrent — no GenServer bottleneck for reads
  - The table lives as long as this process lives (supervised at the top level)

  ## Table structure

  Each record is a 3-tuple: `{key, value, expires_at_ms}`

  Where `key` is typically `{user_id, algorithm}`, e.g.:
    - `{"user:123", :token_bucket}`
    - `{"user:123", :sliding_window}`
    - `{"ip:192.168.1.1", :token_bucket}`

  `expires_at_ms` is a Unix timestamp in milliseconds. A value of `0` means no expiry.
  Stale entries are cleaned up periodically.
  """

  use GenServer
  require Logger

  @table :rate_limiter_store
  # Clean up expired entries every 60 seconds
  @cleanup_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Public API — called from any process, reads go directly to ETS (no GenServer hop)
  # ---------------------------------------------------------------------------

  @doc "Start the ETS owner process."
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get a value by key. Returns `{:ok, value}` or `:miss`.
  This is a direct ETS read — no GenServer involved, microsecond latency.
  """
  @spec get(term()) :: {:ok, term()} | :miss
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if expires_at == 0 or expires_at > now_ms() do
          {:ok, value}
        else
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc """
  Store a value. `ttl_ms: 0` means no expiry.
  Also a direct ETS write — safe because ETS handles concurrent inserts internally.
  """
  @spec put(term(), term(), non_neg_integer()) :: true
  def put(key, value, ttl_ms \\ 0) do
    expires_at = if ttl_ms > 0, do: now_ms() + ttl_ms, else: 0
    :ets.insert(@table, {key, value, expires_at})
  end

  @doc "Delete a key."
  @spec delete(term()) :: true
  def delete(key) do
    :ets.delete(@table, key)
  end

  @doc """
  Return all non-expired records. Used by the LiveView dashboard.
  This is a full table scan — fine for a dashboard, not for hot paths.
  """
  @spec all() :: [{term(), term()}]
  def all do
    now = now_ms()

    :ets.tab2list(@table)
    |> Enum.filter(fn {_key, _value, expires_at} ->
      expires_at == 0 or expires_at > now
    end)
    |> Enum.map(fn {key, value, _expires_at} -> {key, value} end)
  end

  @doc "Number of live entries. Used by telemetry."
  @spec size() :: non_neg_integer()
  def size do
    :ets.info(@table, :size)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks — only responsible for owning the table + cleanup
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    table =
      :ets.new(@table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    Logger.info("[RateLimiter.ETS] Table #{inspect(table)} created")
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    deleted = cleanup_expired()
    if deleted > 0, do: Logger.debug("[RateLimiter.ETS] Cleaned up #{deleted} expired entries")
    schedule_cleanup()
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp cleanup_expired do
    now = now_ms()

    # Match all records where expires_at != 0 AND expires_at <= now
    # ETS match spec: [{match_pattern, guards, result}]
    expired_keys =
      :ets.select(@table, [
        {{:"$1", :"$2", :"$3"},
         [{:andalso, {:"/=", :"$3", 0}, {:"=<", :"$3", now}}],
         [:"$1"]}
      ])

    Enum.each(expired_keys, &:ets.delete(@table, &1))
    length(expired_keys)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
