defmodule Cleat.Slug do
  @moduledoc """
  Turns a human name into a DNS-safe slug (lowercase, dashes, no edges).

  Returns `nil` when the name has no usable characters.
  """

  @doc "Slugifies `name`, or returns `nil` when nothing usable remains."
  def from_name(nil), do: nil

  def from_name(name) when is_binary(name) do
    case name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-") do
      "" -> nil
      slug -> slug
    end
  end
end
