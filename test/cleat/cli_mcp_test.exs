defmodule Cleat.CLIMcpTest do
  use ExUnit.Case, async: true

  alias Cleat.CLI

  test "help documents cleat mcp" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        try do
          CLI.main(["help"])
        catch
          :exit, _ -> :ok
        end
      end)

    assert output =~ "cleat mcp"
  end
end
