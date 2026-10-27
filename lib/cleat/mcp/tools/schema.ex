defmodule Cleat.MCP.Tools.Schema do
  @moduledoc false

  @doc "Panel base URL override accepted by every tool."
  def panel, do: %{"type" => "string", "description" => "Panel base URL override"}

  @doc "Bearer token override accepted by every tool."
  def token, do: %{"type" => "string", "description" => "Bearer token override"}

  @doc "App selector shared by the app-scoped tools."
  def app, do: %{"type" => "string", "description" => "App id or slug"}
end
