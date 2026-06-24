# test/rate_limiter/ets_test.exs

defmodule RateLimiter.ETSTest do
  use ExUnit.Case, async: false

  alias RateLimiter.ETS

  setup do
    # Clear all entries between tests
    :ets.delete_all_objects(:rate_limiter_store)
    :ok
  end

  test "put and get a value" do
    ETS.put({"user:1", :token_bucket}, %{tokens: 10})
    assert {:ok, %{tokens: 10}} = ETS.get({"user:1", :token_bucket})
  end

  test "returns :miss for unknown keys" do
    assert :miss = ETS.get({"user:999", :token_bucket})
  end

  test "delete removes a key" do
    ETS.put({"user:2", :token_bucket}, %{tokens: 5})
    ETS.delete({"user:2", :token_bucket})
    assert :miss = ETS.get({"user:2", :token_bucket})
  end

  test "expired entries return :miss" do
    ETS.put({"user:3", :token_bucket}, %{tokens: 5}, 1)
    Process.sleep(5)
    assert :miss = ETS.get({"user:3", :token_bucket})
  end

  test "all/0 excludes expired entries" do
    ETS.put({"user:4", :token_bucket}, %{tokens: 10})
    ETS.put({"user:5", :token_bucket}, %{tokens: 5}, 1)
    Process.sleep(5)
    keys = ETS.all() |> Enum.map(&elem(&1, 0))
    assert {"user:4", :token_bucket} in keys
    refute {"user:5", :token_bucket} in keys
  end
end
