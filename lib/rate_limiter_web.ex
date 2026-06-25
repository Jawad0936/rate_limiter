defmodule RateLimiterWeb do
  def live_view do
    quote do
      use Phoenix.LiveView, layout: {RateLimiterWeb.Layouts, :app}
      unquote(html_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  defp html_helpers do
    quote do
      use Phoenix.HTML
      import Phoenix.LiveView.Helpers
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
