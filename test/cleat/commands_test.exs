defmodule Cleat.CommandsTest do
  use ExUnit.Case, async: false

  alias Cleat.Commands

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
end
