defmodule Cleat.OutputTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "table renders headers and aligned rows" do
    output =
      capture_io(fn ->
        Cleat.Output.table([["1", "alpha"], ["22", "b"]], ["ID", "NAME"])
      end)

    assert output =~ "ID"
    assert output =~ "NAME"
    assert output =~ "22"
    assert output =~ "alpha"
  end

  test "table with no rows still prints headers" do
    output = capture_io(fn -> Cleat.Output.table([], ["ID", "NAME"]) end)
    assert output =~ "ID  NAME"
  end

  test "datetime formats UTC timestamps" do
    assert Cleat.Output.datetime(~U[2026-09-19 04:47:43Z]) == "2026-09-19 04:47:43"
    assert Cleat.Output.datetime(nil) == "—"
    assert Cleat.Output.datetime("2026-01-01") == "2026-01-01"
  end

  test "json prints a pretty document" do
    output = capture_io(fn -> Cleat.Output.json(%{"a" => 1}) end)
    assert output =~ ~s("a": 1)
  end
end
