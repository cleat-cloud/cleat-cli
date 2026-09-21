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
end
