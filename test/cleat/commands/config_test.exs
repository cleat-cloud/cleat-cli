defmodule Cleat.Commands.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands.Config

  setup do
    path =
      Path.join(System.tmp_dir!(), "cleat-config-cmd-#{System.unique_integer([:positive])}.json")

    System.put_env("CLEAT_CONFIG", path)
    on_exit(fn -> System.delete_env("CLEAT_CONFIG") end)
    {:ok, path: path}
  end

  test "sets and gets the base domain, normalized" do
    capture_io(fn ->
      assert :ok = Config.run(["set", "base_domain", "Sites.Example.com."], %{})
    end)

    assert Cleat.Config.get("base_domain") == "sites.example.com"

    output = capture_io(fn -> assert :ok = Config.run(["get", "base_domain"], %{}) end)
    assert output =~ "sites.example.com"
  end

  test "unsets a key" do
    Cleat.Config.put("base_domain", "sites.example.com")

    capture_io(fn -> assert :ok = Config.run(["unset", "base_domain"], %{}) end)

    assert Cleat.Config.get("base_domain") == nil
  end

  test "rejects unknown keys" do
    assert {:error, message} = Config.run(["set", "nope", "x"], %{})
    assert message =~ "unknown key"
  end

  test "list masks the token" do
    Cleat.Config.put("token", "cleat_abcdefghijklmnop")

    output = capture_io(fn -> assert :ok = Config.run(["list"], %{}) end)
    assert output =~ "cleat_ab…"
    refute output =~ "cleat_abcdefghijklmnop"
  end
end
