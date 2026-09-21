defmodule Cleat.SlugTest do
  use ExUnit.Case, async: true

  alias Cleat.Slug

  test "lowercases and dashes non-alphanumerics" do
    assert Slug.from_name("Minha Loja") == "minha-loja"
  end

  test "trims dashes from the edges" do
    assert Slug.from_name("__weird--name__") == "weird-name"
  end

  test "returns nil when nothing usable remains" do
    assert Slug.from_name("---") == nil
    assert Slug.from_name("") == nil
    assert Slug.from_name(nil) == nil
  end
end
