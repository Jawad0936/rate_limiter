defmodule RateLimiter.SlidingWindowTest do
  use ExUnit.Case, async: false

  alias RateLimiter.SlidingWindow

  @user "test_user_sw"

  setup do
    :ets.delete_all_objects(:rate_limiter_store)

    # Small limit and short window so tests run fast
    config = %{limit: 3, window_ms: 200}
    {:ok, pid} = SlidingWindow.start_link(user_id: @user, config: config)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    {:ok, pid: pid}
  end

  test "allows requests up to the limit" do
    for _ <- 1..3 do
      assert {:allow, _} = SlidingWindow.allow?(@user)
    end
  end

  test "denies requests once limit is reached" do
    for _ <- 1..3, do: SlidingWindow.allow?(@user)
    assert {:deny, retry_ms} = SlidingWindow.allow?(@user)
    assert retry_ms > 0
  end

  test "requests_remaining decrements correctly" do
    assert {:allow, 2} = SlidingWindow.allow?(@user)
    assert {:allow, 1} = SlidingWindow.allow?(@user)
    assert {:allow, 0} = SlidingWindow.allow?(@user)
  end

  test "old requests fall outside the window and free up capacity" do
    for _ <- 1..3, do: SlidingWindow.allow?(@user)
    assert {:deny, _} = SlidingWindow.allow?(@user)

    # Wait for the window to pass
    Process.sleep(210)
    assert {:allow, _} = SlidingWindow.allow?(@user)
  end

  test "retry_after is precise — close to window boundary" do
    for _ <- 1..3, do: SlidingWindow.allow?(@user)
    assert {:deny, retry_ms} = SlidingWindow.allow?(@user)
    # With a 200ms window, retry can't be more than 200ms away
    assert retry_ms <= 200
  end

  test "state/1 reads from ETS without hitting the GenServer" do
    SlidingWindow.allow?(@user)
    assert {:ok, %{timestamps: [_], limit: 3}} = SlidingWindow.state(@user)
  end

  test "timestamp list is pruned — never grows beyond window" do
    # Make 3 requests, wait for window, make 3 more
    for _ <- 1..3, do: SlidingWindow.allow?(@user)
    Process.sleep(210)
    for _ <- 1..3, do: SlidingWindow.allow?(@user)

    {:ok, %{timestamps: timestamps}} = SlidingWindow.state(@user)
    # Should only contain the recent 3, not all 6
    assert length(timestamps) == 3
  end
end
