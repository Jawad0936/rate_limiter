defmodule RateLimiterWeb.Layouts do
  use Phoenix.Component

  def render("root.html", assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()}/>
        <title>Rate Limiter Dashboard</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0f172a; color: #e2e8f0; }
        </style>
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def render("app.html", assigns) do
    ~H"""
    <%= @inner_content %>
    """
  end
end
