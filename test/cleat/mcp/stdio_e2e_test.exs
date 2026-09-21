defmodule Cleat.MCP.StdioE2ETest do
  use ExUnit.Case, async: true

  alias Cleat.MCP.Server

  test "answers initialize and tools/list over a byte stream" do
    input =
      ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n) <>
        ~s({"jsonrpc":"2.0","id":2,"method":"tools/list"}\n)

    {output, _} = collect(input)
    lines = String.split(output, "\n", trim: true)

    assert length(lines) == 2

    [first, second] = Enum.map(lines, &Jason.decode!/1)
    assert first["id"] == 1
    assert first["result"]["serverInfo"]["name"] == "cleat"
    assert Enum.any?(second["result"]["tools"], &(&1["name"] == "deploy"))
  end

  test "ignores notifications" do
    input = ~s({"jsonrpc":"2.0","method":"notifications/initialized"}\n)
    {output, _} = collect(input)
    assert String.trim(output) == ""
  end

  defp collect(input) do
    in_path = Path.join(System.tmp_dir!(), "cleat_e2e_in_#{System.unique_integer([:positive])}")
    out_path = Path.join(System.tmp_dir!(), "cleat_e2e_out_#{System.unique_integer([:positive])}")
    File.write!(in_path, input)

    on_exit(fn ->
      File.rm(in_path)
      File.rm(out_path)
    end)

    in_device = File.open!(in_path, [:read, :binary])
    out_device = File.open!(out_path, [:write, :binary])

    Server.run(input: in_device, output: out_device)

    File.close(in_device)
    File.close(out_device)

    {File.read!(out_path), :ok}
  end
end
