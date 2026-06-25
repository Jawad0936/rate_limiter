defmodule RateLimiterWeb.ErrorView do
  def render("404.html", _assigns), do: "Not found"
  def render("500.html", _assigns), do: "Server error"
  def render(_, _assigns), do: "Error"
end
