defmodule Cleat.PollerTest do
  use ExUnit.Case, async: true

  alias Cleat.Poller

  import ExUnit.CaptureIO

  test "retries transient errors before completing" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fetch = fn ->
      attempt = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

      if attempt < 2, do: {:error, "connection reset"}, else: {:ok, %{status: "success"}}
    end

    step = fn data, _state ->
      if data.status == "success", do: :done, else: {:continue, nil}
    end

    capture_io(fn ->
      assert :ok = Poller.poll(fetch, step, nil, interval: 1)
    end)

    assert Agent.get(counter, & &1) == 3
  end

  test "gives up after repeated failures" do
    fetch = fn -> {:error, "panel offline"} end
    step = fn _data, _state -> :done end

    capture_io(fn ->
      assert {:error, message} = Poller.poll(fetch, step, nil, interval: 1)
      assert message =~ "gave up"
    end)
  end

  test "stops without sleeping when already terminal" do
    fetch = fn -> {:ok, %{status: "success"}} end
    step = fn _data, _state -> :done end

    assert :ok = Poller.poll(fetch, step, nil, interval: 60_000)
  end
end
