defmodule Cleat.CommandsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cleat.Commands

  @isolated_env ~w(CLEAT_CONFIG CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN)

  # Isolate from the developer's real config file and domain env vars.
  setup do
    path = Path.join(System.tmp_dir!(), "cleat_cfg_#{System.unique_integer([:positive])}.json")
    previous = Map.new(@isolated_env, &{&1, System.get_env(&1)})

    System.put_env("CLEAT_CONFIG", path)
    Enum.each(~w(CLEAT_BASE_DOMAIN CLEAT_SITES_BASE_DOMAIN), &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
      File.rm(path)
    end)

    :ok
  end

  test "prefers --host when given" do
    assert {:ok, "app.example.com"} =
             Commands.host(%{host: "App.Example.com", subdomain: "other"})
  end

  test "builds the host from --subdomain and --base-domain" do
    assert {:ok, "landing.sites.example.com"} =
             Commands.host(%{subdomain: "Landing", base_domain: "Sites.Example.com"})
  end

  test "falls back to the CLEAT_BASE_DOMAIN env var" do
    System.put_env("CLEAT_BASE_DOMAIN", "sites.example.com")
    on_exit(fn -> System.delete_env("CLEAT_BASE_DOMAIN") end)

    assert {:ok, "demo.sites.example.com"} = Commands.host(%{subdomain: "demo"})
  end

  test "errors when no host or subdomain is given" do
    assert {:error, :missing_host} = Commands.host(%{})
  end

  test "errors when a subdomain is given without a base domain" do
    assert {:error, message} = Commands.host(%{subdomain: "demo"})
    assert message =~ "no base domain configured"
  end

  test "rejects dotted subdomains" do
    assert {:error, message} =
             Commands.host(%{subdomain: "a.b", base_domain: "sites.example.com"})

    assert message =~ "single label"
  end

  test "rejects invalid subdomain characters" do
    assert {:error, message} =
             Commands.host(%{subdomain: "Bad_Name", base_domain: "sites.example.com"})

    assert message =~ "invalid subdomain"
  end

  test "reads the token from a file" do
    path = tmp_file("cleat-token")
    File.write!(path, "cleat_from_file\n")

    assert Commands.token(%{token_file: path}) == "cleat_from_file"
  end

  test "reads the token from stdin when --token is -" do
    capture_io("cleat_from_stdin\n", fn ->
      assert Commands.token(%{token: "-"}) == "cleat_from_stdin"
    end)
  end

  test "reads the password from a file" do
    path = tmp_file("cleat-password")
    File.write!(path, "s3cret\n")

    assert Commands.password(%{password_file: path}) == "s3cret"
  end

  test "reads the password from stdin when --password is -" do
    capture_io("s3cret\n", fn ->
      assert Commands.password(%{password: "-"}) == "s3cret"
    end)
  end

  test "sites_base_domain prefers --sites-base-domain over the env var" do
    System.put_env("CLEAT_SITES_BASE_DOMAIN", "env.example.com")

    assert Commands.sites_base_domain(%{sites_base_domain: "flag.example.com"}) ==
             "flag.example.com"
  end

  test "sites_base_domain reads CLEAT_SITES_BASE_DOMAIN when the flag is absent" do
    System.put_env("CLEAT_SITES_BASE_DOMAIN", "env.example.com")

    assert Commands.sites_base_domain(%{}) == "env.example.com"
  end

  test "sites_base_domain ignores an empty --sites-base-domain and falls through to env" do
    System.put_env("CLEAT_SITES_BASE_DOMAIN", "env.example.com")

    assert Commands.sites_base_domain(%{sites_base_domain: ""}) == "env.example.com"
  end

  test "sites_base_domain falls back to base_domain" do
    Cleat.Config.put("base_domain", "apps.example.com")

    assert Commands.sites_base_domain(%{}) == "apps.example.com"
  end

  test "static_host builds <slug>.<sites_base_domain>" do
    assert {:ok, "minha-loja.sites.example.com"} =
             Commands.static_host("minha-loja", %{sites_base_domain: "sites.example.com"})
  end

  test "static_host errors without a configured sites base domain" do
    {:error, message} = Commands.static_host("x", %{sites_base_domain: nil})
    assert message =~ "sites_base_domain"
  end

  test "static_host slugifies the slug" do
    assert {:ok, "minha-loja.sites.example.com"} =
             Commands.static_host("Minha Loja", %{sites_base_domain: "sites.example.com"})
  end

  test "static_host errors on a nil slug" do
    assert {:error, _} =
             Cleat.Commands.static_host(nil, %{sites_base_domain: "sites.example.com"})
  end

  defp tmp_file(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
