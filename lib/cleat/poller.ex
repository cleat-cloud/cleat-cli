defmodule Cleat.Poller do
  @moduledoc """
  Polls the panel until a terminal state, tolerating transient failures.

  `fetch` returns `{:ok, data}` or `{:error, message}`. `step` receives the data
  and the previous state and returns `{:continue, new_state}`, `:done`, or
  `{:error, message}`. Consecutive fetch errors are retried with backoff before
  giving up.
  """

  alias Cleat.Output

  @initial_interval 2_000
  @max_interval 15_000
  @max_consecutive_errors 5

  def poll(fetch, step, initial_state, opts \\ []) do
    interval = Keyword.get(opts, :interval, @initial_interval)
    loop(fetch, step, initial_state, interval, 0)
  end

  defp loop(fetch, step, state, interval, errors) do
    case fetch.() do
      {:ok, data} ->
        case step.(data, state) do
          {:continue, new_state} -> sleep_loop(fetch, step, new_state, interval, 0)
          :done -> :ok
          {:error, _message} = error -> error
        end

      {:error, message} ->
        if errors + 1 >= @max_consecutive_errors do
          {:error, "#{message} (gave up after #{errors + 1} attempts)"}
        else
          Output.warn("transient error: #{message} — retrying")
          sleep_loop(fetch, step, state, interval, errors + 1)
        end
    end
  end

  defp sleep_loop(fetch, step, state, interval, errors) do
    Process.sleep(interval)
    loop(fetch, step, state, min(round(interval * 1.5), @max_interval), errors)
  end
end
