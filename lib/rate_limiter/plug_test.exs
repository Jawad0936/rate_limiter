defmodule RateLimiter.PlugTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias RateLimiter.Plug, as: RLPlug
  alias RateLimiter.UserSupervisor

  setup do
  :ets.delete_all_objects(:rate_limiter_store)
  UserSupervisor.stop_user("ip:127.0.0.1")
  UserSupervisor.stop_user("user:abc123")
  UserSupervisor.stop_user("sw_plug_test_user")
  Process.sleep(20)
  :ok
end

  defp make_request(opts) do
    conn(:get, "/test")
    |> RLPlug.call(RLPlug.init(opts))
  end

  defp make_authed_request(user_id, opts) do
    conn(:get, "/test")
    |> assign(:current_user, %{id: user_id})
    |> RLPlug.call(RLPlug.init(opts))
  end

  @base_opts [algorithm: :token_bucket, token_bucket: %{capacity: 3, refill_rate_per_sec: 10}]

  test "allows requests under the limit" do
    conn = make_request(@base_opts)
    refute conn.halted
    assert get_resp_header(conn, "x-ratelimit-limit") == ["3"]
    assert get_resp_header(conn, "x-ratelimit-algorithm") == ["token_bucket"]
  end

  test "sets x-ratelimit-remaining header" do
    conn = make_request(@base_opts)
    [remaining] = get_resp_header(conn, "x-ratelimit-remaining")
    assert String.to_integer(remaining) >= 0
  end

  test "returns 429 when limit exceeded" do
    for _ <- 1..3, do: make_request(@base_opts)
    conn = make_request(@base_opts)
    assert conn.halted
    assert conn.status == 429
  end

  test "sets Retry-After header on 429" do
    for _ <- 1..3, do: make_request(@base_opts)
    conn = make_request(@base_opts)
    assert conn.status == 429
    assert [retry] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry) >= 1
  end

  test "429 response body is valid JSON with expected fields" do
    for _ <- 1..3, do: make_request(@base_opts)
    conn = make_request(@base_opts)
    body = Jason.decode!(conn.resp_body)
    assert body["error"] == "rate_limit_exceeded"
    assert body["algorithm"] == "token_bucket"
    assert is_integer(body["retry_after"])
  end

  test "falls back to IP when no current_user assigned" do
    conn = make_request(@base_opts)
    refute conn.halted
    # IP bucket is separate — confirm it works
    assert get_resp_header(conn, "x-ratelimit-algorithm") == ["token_bucket"]
  end

  test "uses current_user when assigned" do
    conn = make_authed_request("abc123", @base_opts)
    refute conn.halted
    assert get_resp_header(conn, "x-ratelimit-algorithm") == ["token_bucket"]
  end

  test "authenticated and IP users have separate buckets" do
    # Drain the IP bucket
    for _ <- 1..3, do: make_request(@base_opts)
    assert make_request(@base_opts).halted

    # Authenticated user still has a full bucket
    conn = make_authed_request("abc123", @base_opts)
    refute conn.halted
  end

  test "sliding window algorithm works via plug" do
  opts = [algorithm: :sliding_window, sliding_window: %{limit: 2, window_ms: 500}]

  # Use a unique user ID so this test is fully isolated
  conn = fn ->
    conn(:get, "/test")
    |> assign(:current_user, %{id: "sw_plug_test_user"})
    |> RLPlug.call(RLPlug.init(opts))
  end

  assert conn.().halted == false
  assert conn.().halted == false
  denied = conn.()
  assert denied.halted == true
  assert denied.status == 429
  assert get_resp_header(denied, "x-ratelimit-algorithm") == ["sliding_window"]
end
end
