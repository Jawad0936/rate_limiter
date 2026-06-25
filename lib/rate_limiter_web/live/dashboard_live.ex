defmodule RateLimiterWeb.DashboardLive do
  use Phoenix.LiveView

  alias RateLimiter.{ETS, UserSupervisor}

  @refresh_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok, assign(socket,
      users: load_users(),
      total_allowed: 0,
      total_denied: 0,
      last_updated: time_now()
    )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign(socket, users: load_users(), last_updated: time_now())}
  end

  @impl true
  def handle_event("stop_user", %{"user_id" => user_id}, socket) do
    UserSupervisor.stop_user(user_id)
    {:noreply, assign(socket, users: load_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="min-height:100vh; padding: 2rem;">

      <div style="max-width:1100px; margin:0 auto;">

        <!-- Header -->
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:2rem;">
          <div>
            <h1 style="font-size:1.75rem; font-weight:700; color:#f8fafc;">
              ⚡ Rate Limiter Dashboard
            </h1>
            <p style="color:#94a3b8; font-size:0.875rem; margin-top:0.25rem;">
              Real-time per-user rate limit state · refreshes every second
            </p>
          </div>
          <div style="color:#64748b; font-size:0.8rem;">
            Last updated: <%= @last_updated %>
          </div>
        </div>

        <!-- Stats row -->
        <div style="display:grid; grid-template-columns:repeat(3,1fr); gap:1rem; margin-bottom:2rem;">
          <div style={card_style("#1e293b")}>
            <div style="color:#94a3b8; font-size:0.75rem; text-transform:uppercase; letter-spacing:0.05em;">Active Users</div>
            <div style="font-size:2rem; font-weight:700; color:#38bdf8; margin-top:0.25rem;">
              <%= length(@users) %>
            </div>
          </div>
          <div style={card_style("#1e293b")}>
            <div style="color:#94a3b8; font-size:0.75rem; text-transform:uppercase; letter-spacing:0.05em;">Token Bucket</div>
            <div style="font-size:2rem; font-weight:700; color:#a78bfa; margin-top:0.25rem;">
              <%= count_algo(@users, :token_bucket) %>
            </div>
          </div>
          <div style={card_style("#1e293b")}>
            <div style="color:#94a3b8; font-size:0.75rem; text-transform:uppercase; letter-spacing:0.05em;">Sliding Window</div>
            <div style="font-size:2rem; font-weight:700; color:#34d399; margin-top:0.25rem;">
              <%= count_algo(@users, :sliding_window) %>
            </div>
          </div>
        </div>

        <!-- User table -->
        <%= if @users == [] do %>
          <div style={card_style("#1e293b") <> " text-align:center; padding:3rem;"}>
            <div style="font-size:3rem; margin-bottom:1rem;">🪣</div>
            <div style="color:#94a3b8;">No active users yet.</div>
            <div style="color:#64748b; font-size:0.875rem; margin-top:0.5rem;">
              Make a request through the Plug to see users appear here.
            </div>
          </div>
        <% else %>
          <div style={card_style("#1e293b")}>
            <table style="width:100%; border-collapse:collapse;">
              <thead>
                <tr style="border-bottom:1px solid #334155;">
                  <th style={th_style()}>User</th>
                  <th style={th_style()}>Algorithm</th>
                  <th style={th_style()}>State</th>
                  <th style={th_style()}>Utilization</th>
                  <th style={th_style()}>Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for user <- @users do %>
                  <tr style="border-bottom:1px solid #1e293b;">
                    <td style={td_style()}>
                      <span style="font-family:monospace; color:#38bdf8; font-size:0.875rem;">
                        <%= user.user_id %>
                      </span>
                    </td>
                    <td style={td_style()}>
                      <span style={"display:inline-block; padding:0.2rem 0.6rem; border-radius:9999px; font-size:0.75rem; font-weight:600; background:#{algo_bg(user.algorithm)}; color:#{algo_color(user.algorithm)};"}>
                        <%= user.algorithm %>
                      </span>
                    </td>
                    <td style={td_style()}>
                      <%= render_state(user) %>
                    </td>
                    <td style={td_style()}>
                      <%= render_bar(user) %>
                    </td>
                    <td style={td_style()}>
                      <button
                        phx-click="stop_user"
                        phx-value-user_id={user.user_id}
                        style="padding:0.25rem 0.75rem; background:#7f1d1d; color:#fca5a5; border:none; border-radius:0.375rem; font-size:0.75rem; cursor:pointer;">
                        Stop
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>

      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_users do
    running = UserSupervisor.list_users()

    Enum.map(running, fn %{user_id: user_id, algorithm: algo} ->
      state = case algo do
        :token_bucket  ->
          case ETS.get({user_id, :token_bucket}) do
            {:ok, s} -> s
            :miss    -> nil
          end
        :sliding_window ->
          case ETS.get({user_id, :sliding_window}) do
            {:ok, s} -> s
            :miss    -> nil
          end
      end

      %{user_id: user_id, algorithm: algo, state: state}
    end)
    |> Enum.sort_by(& &1.user_id)
  end

  defp render_state(%{algorithm: :token_bucket, state: nil}), do: "..."
  defp render_state(%{algorithm: :token_bucket, state: s}) do
    "#{Float.round(s.tokens, 1)} / #{s.capacity} tokens"
  end

  defp render_state(%{algorithm: :sliding_window, state: nil}), do: "..."
  defp render_state(%{algorithm: :sliding_window, state: s}) do
    count = length(s.timestamps)
    "#{count} / #{s.limit} requests"
  end

  defp render_bar(%{algorithm: :token_bucket, state: nil}), do: ""
  defp render_bar(%{algorithm: :token_bucket, state: s}) do
    pct = Float.round(s.tokens / s.capacity * 100, 1)
    color = cond do
      pct > 60 -> "#22c55e"
      pct > 25 -> "#f59e0b"
      true     -> "#ef4444"
    end
    bar(pct, color)
  end

  defp render_bar(%{algorithm: :sliding_window, state: nil}), do: ""
  defp render_bar(%{algorithm: :sliding_window, state: s}) do
    count = length(s.timestamps)
    pct   = Float.round(count / s.limit * 100, 1)
    color = cond do
      pct < 40 -> "#22c55e"
      pct < 75 -> "#f59e0b"
      true     -> "#ef4444"
    end
    bar(pct, color)
  end

  defp bar(pct, color) do
    assigns = %{pct: pct, color: color}
    ~H"""
    <div style="display:flex; align-items:center; gap:0.5rem;">
      <div style="flex:1; height:6px; background:#334155; border-radius:9999px; overflow:hidden;">
        <div style={"height:100%; width:#{@pct}%; background:#{@color}; border-radius:9999px; transition:width 0.3s ease;"}></div>
      </div>
      <span style="font-size:0.75rem; color:#94a3b8; width:3rem; text-align:right;"><%= @pct %>%</span>
    </div>
    """
  end

  defp count_algo(users, algo), do: Enum.count(users, &(&1.algorithm == algo))

  defp card_style(bg), do: "background:#{bg}; border-radius:0.75rem; padding:1.25rem; border:1px solid #334155;"
  defp th_style, do: "text-align:left; padding:0.75rem 1rem; color:#64748b; font-size:0.75rem; text-transform:uppercase; letter-spacing:0.05em; font-weight:600;"
  defp td_style, do: "padding:0.875rem 1rem; color:#cbd5e1; font-size:0.875rem;"

  defp algo_bg(:token_bucket),   do: "#2e1065"
  defp algo_bg(:sliding_window), do: "#064e3b"
  defp algo_color(:token_bucket),   do: "#a78bfa"
  defp algo_color(:sliding_window), do: "#34d399"

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)
  defp time_now, do: Time.utc_now() |> Time.truncate(:second) |> Time.to_string()
end
