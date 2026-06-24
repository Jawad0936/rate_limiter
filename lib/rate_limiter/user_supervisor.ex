defmodule RateLimiter.UserSupervisor do
  @moduledoc """
  DynamicSupervisor that manages per-user rate limiter processes.

  ## Design

  One GenServer per user, started on first request and kept alive.
  The Registry prevents duplicate processes — if two requests arrive
  simultaneously for the same new user, only one GenServer is started.

  ## Process tree per user

      RateLimiter.UserSupervisor
      ├── TokenBucket  (user: "user:123")
      ├── SlidingWindow (user: "user:123")
      ├── TokenBucket  (user: "ip:192.168.1.1")
      └── ...

  ## Restart strategy

  Each child uses the default `:permanent` restart — if a GenServer
  crashes, the supervisor restarts it with a fresh state. For a rate
  limiter this is acceptable: a crashed bucket resets, which is
  slightly generous to the user but never unsafe.
  """

  use DynamicSupervisor
  require Logger

  alias RateLimiter.{TokenBucket, SlidingWindow}

  @algorithms [:token_bucket, :sliding_window]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Ensure both algorithm GenServers are running for `user_id`.
  Called by the Plug on every request — must be fast when already started.

  Returns `:ok`.
  """
  @spec ensure_started(String.t(), keyword()) :: :ok
  def ensure_started(user_id, opts \\ []) do
    Enum.each(@algorithms, fn algo ->
      ensure_started_for(user_id, algo, opts)
    end)
  end

  @doc """
  List all running rate limiter processes.
  Used by the LiveView dashboard.
  """
  @spec list_users() :: [%{user_id: String.t(), algorithm: atom(), pid: pid()}]
  def list_users do
    Registry.select(RateLimiter.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {{module, user_id}, pid} ->
      algo = case module do
        TokenBucket    -> :token_bucket
        SlidingWindow  -> :sliding_window
      end
      %{user_id: user_id, algorithm: algo, pid: pid}
    end)
  end

  @doc "Stop all processes for a user. Useful for testing and admin."
  @spec stop_user(String.t()) :: :ok
  def stop_user(user_id) do
    Enum.each(@algorithms, fn algo ->
      module = module_for(algo)
      case GenServer.whereis(module.via(user_id)) do
        nil -> :ok
        pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # DynamicSupervisor callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

defp ensure_started_for(user_id, algo, opts) do
  module = module_for(algo)

  child_spec =
    case Keyword.get(opts, algo) do
      nil    -> {module, user_id: user_id}
      config when map_size(config) == 0 -> {module, user_id: user_id}
      config -> {module, user_id: user_id, config: config}
    end

  case DynamicSupervisor.start_child(__MODULE__, child_spec) do
    {:ok, _pid}                        -> :ok
    {:error, {:already_started, _pid}} -> :ok
    {:error, reason}                   ->
      Logger.error("[UserSupervisor] Failed to start #{algo} for #{user_id}: #{inspect(reason)}")
      :ok
  end
end
  defp module_for(:token_bucket),    do: TokenBucket
  defp module_for(:sliding_window),  do: SlidingWindow
end
