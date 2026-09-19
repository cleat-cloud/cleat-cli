defmodule Cleat.ConfigTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(System.tmp_dir!(), "cleat-config-test-#{System.unique_integer([:positive])}")

    path = Path.join(dir, "config.json")
    System.put_env("CLEAT_CONFIG", path)

    on_exit(fn ->
      System.delete_env("CLEAT_CONFIG")
      File.rm_rf(dir)
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

  test "the config file is private (0600) and its dir is 0700", %{path: path} do
    assert :ok = Cleat.Config.save(%{"token" => "cleat_secret"})

    assert file_mode(path) == 0o600
    assert file_mode(Path.dirname(path)) == 0o700
  end

  defp file_mode(path) do
    path |> File.stat!() |> Map.fetch!(:mode) |> Bitwise.band(0o777)
  end
end
