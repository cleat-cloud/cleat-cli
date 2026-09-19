defmodule Cleat.Commands.CompletionsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Cleat.Commands.Completions

  test "prints a bash completion script" do
    output = capture_io(fn -> assert :ok = Completions.run(["bash"], %{}) end)

    assert output =~ "complete -F _cleat cleat"
    assert output =~ "deploy"
  end

  test "prints a zsh completion script" do
    output = capture_io(fn -> assert :ok = Completions.run(["zsh"], %{}) end)

    assert output =~ "#compdef cleat"
  end

  test "rejects unsupported shells" do
    assert {:error, message} = Completions.run(["fish"], %{})
    assert message =~ "unsupported shell"
  end

  test "requires a shell argument" do
    assert {:error, message} = Completions.run([], %{})
    assert message =~ "usage"
  end
end
