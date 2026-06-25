defmodule RateLimiter.UserSupervisorTest do
  use ExUnit.Case, async: false

  alias RateLimiter.{UserSupervisor, TokenBucket, SlidingWindow}

  @user "supervisor_test_user"

  setup do
    :ets.delete_all_objects(:rate_limiter_store)
    UserSupervisor.stop_user(@user)
    :ok
  end

  test "ensure_started/1 starts both algorithm processes" do
    :ok = UserSupervisor.ensure_started(@user)

    assert is_pid(GenServer.whereis(TokenBucket.via(@user)))
    assert is_pid(GenServer.whereis(SlidingWindow.via(@user)))
  end

  test "ensure_started/1 is idempotent — safe to call on every request" do
    :ok = UserSupervisor.ensure_started(@user)
    :ok = UserSupervisor.ensure_started(@user)
    :ok = UserSupervisor.ensure_started(@user)

    # Still only one process per algorithm
    assert [_] = Registry.lookup(RateLimiter.Registry, {TokenBucket, @user})
    assert [_] = Registry.lookup(RateLimiter.Registry, {SlidingWindow, @user})
  end

  test "processes are supervised — restart after crash" do
    :ok = UserSupervisor.ensure_started(@user)
    pid = GenServer.whereis(TokenBucket.via(@user))

    # Kill the process
    Process.exit(pid, :kill)
    Process.sleep(50)  # give supervisor time to restart

    new_pid = GenServer.whereis(TokenBucket.via(@user))
    assert is_pid(new_pid)
    assert new_pid != pid  # it's a new process
  end

  test "list_users/0 returns running processes" do
    :ok = UserSupervisor.ensure_started(@user)
    users = UserSupervisor.list_users()

    user_ids = Enum.map(users, & &1.user_id)
    assert @user in user_ids
  end

  test "stop_user/1 terminates both processes" do
    :ok = UserSupervisor.ensure_started(@user)
    :ok = UserSupervisor.stop_user(@user)
    Process.sleep(20)

    assert nil == GenServer.whereis(TokenBucket.via(@user))
    assert nil == GenServer.whereis(SlidingWindow.via(@user))
  end
end
