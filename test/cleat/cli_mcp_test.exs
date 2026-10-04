defmodule Cleat.CLIMcpTest do
  use ExUnit.Case, async: true

  alias Cleat.CLI

  test "usage documents the mcp command" do
    usage = CLI.usage()

    assert usage =~ "cleat mcp"
    assert usage =~ "Run as an MCP server on stdio"
    assert usage =~ "claude mcp add cleat -- cleat mcp"
  end

  test "mcp is listed in the Project section" do
    usage = CLI.usage()
    [project_section | _] = String.split(usage, "Resources")
    assert project_section =~ ~r/^\s*mcp\s/m
  end

  test "usage documents signals health, metrics and alerts" do
    usage = CLI.usage()
    assert usage =~ "signals health"
    assert usage =~ "signals metrics"
    assert usage =~ "signals pages"
    assert usage =~ "apps query"
    assert usage =~ "signals alerts"
  end

  test "usage documents signals traces and sampling" do
    usage = CLI.usage()
    assert usage =~ "signals traces"
    assert usage =~ "signals sampling"
  end
end
