defmodule Cleat.ConfigTest do
  use ExUnit.Case, async: false

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "cleat-config-#{System.unique_integer([:positive])}.json"
      )

    System.put_env("CLEAT_CONFIG", path)

    on_exit(fn ->
      System.delete_env("CLEAT_CONFIG")
      File.rm(path)
    end)

    {:ok, path: path}
  end

  test "save and load round trip", %{path: path} do
    assert :ok = Cleat.Config.save(%{"panel_url" => "https://p.test", "token" => "t"})
    assert File.exists?(path)
    assert Cleat.Config.load() == %{"panel_url" => "https://p.test", "token" => "t"}
    assert Cleat.Config.panel_url() == "https://p.test"
    assert Cleat.Config.token() == "t"
  end

  test "put preserves existing keys, delete removes one" do
    Cleat.Config.put("panel_url", "https://p.test")
    Cleat.Config.put("token", "tok")

    assert Cleat.Config.token() == "tok"

    Cleat.Config.delete("token")

    assert Cleat.Config.token() == nil
    assert Cleat.Config.panel_url() == "https://p.test"
  end

  test "missing file yields empty config" do
    assert Cleat.Config.load() == %{}
    assert Cleat.Config.panel_url() == nil
    assert Cleat.Config.token() == nil
  end
end
