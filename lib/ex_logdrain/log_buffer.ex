defmodule ExLogdrain.LogBuffer do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(log) do
    GenServer.cast(__MODULE__, {:enqueue, log})
  end

  @impl true
  def init(initial_state) do
    IO.puts(">>> LOG BUFFER GENSERVER HAS STARTED INITIALIZATION <<<")
    schedule_flush()
    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:enqueue, log}, state) do
    {:noreply, [log | state]}
  end

  @impl true
  def handle_info(:flush, []) do
    schedule_flush()
    {:noreply, []}
  end

  def handle_info(:flush, logs_buffer) do
    Logger.info("Flushing #{length(logs_buffer)} logs to DuckDB...")

    ExLogdrain.Repo.insert_batch(Enum.reverse(logs_buffer))

    schedule_flush()
    {:noreply, []}
  end

  defp schedule_flush do
    seconds = Application.get_env(:ex_logdrain, :flush_interval, 5)
    Process.send_after(self(), :flush, :timer.seconds(seconds))
  end
end
