defmodule RateLimiter.TokenBucketTest do
  use ExUnit.Case, async: false

  alias RateLimiter.TokenBucket

  @user "test_user_tb"

    setup do
      :ets.delete_all_objects(:rate_limiter_store)

      config = %{capacity: 5, refill_rate_per_sec: 10}
      {:ok, pid} = TokenBucket.start_link(user_id: @user, config: config)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      {:ok, pid: pid}
    end

  test "allows requests up to capacity" do
    for _ <- 1..5 do
      assert {:allow, _} = TokenBucket.allow?(@user)
    end
  end

  test "denies requests when bucket is empty" do
    for _ <- 1..5, do: TokenBucket.allow?(@user)
    assert {:deny, retry_ms} = TokenBucket.allow?(@user)
    assert retry_ms > 0
  end

  test "tokens refill over time" do
    # Drain the bucket
    for _ <- 1..5, do: TokenBucket.allow?(@user)
    assert {:deny, _} = TokenBucket.allow?(@user)

    # Wait for refill — 10 tokens/sec = 1 token per 100ms
    Process.sleep(120)
    assert {:allow, _} = TokenBucket.allow?(@user)
  end

  test "state/1 reads from ETS without hitting the GenServer" do
    TokenBucket.allow?(@user)
    assert {:ok, %{tokens: tokens}} = TokenBucket.state(@user)
    assert tokens < 5.0
  end

  test "tokens never exceed capacity" do
    # Start full, wait, check it doesn't overflow
    Process.sleep(200)
    assert {:ok, %{tokens: tokens, capacity: cap}} = TokenBucket.state(@user)
    assert tokens <= cap * 1.0
  end

  test "retry_after is a positive integer when denied" do
    for _ <- 1..5, do: TokenBucket.allow?(@user)
    assert {:deny, retry_ms} = TokenBucket.allow?(@user)
    assert is_integer(retry_ms)
    assert retry_ms > 0
  end
end
