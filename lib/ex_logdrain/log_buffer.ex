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

    ordered_logs = Enum.reverse(logs_buffer)

    insert_batch_to_duckdb(ordered_logs)

    schedule_flush()
    {:noreply, []}
  end

  defp schedule_flush do
    seconds = Application.get_env(:ex_logdrain, :flush_interval, 5)
    interval_ms = :timer.seconds(seconds)
    Process.send_after(self(), :flush, interval_ms)
  end

  defp insert_batch_to_duckdb(logs) do
    IO.puts("Insert Batch")

    Enum.each(logs, fn log ->
      sql = "INSERT INTO vercel_logs (id, team_id, message, runtime) VALUES ($1, $2, $3, $4);"
      # DuckDB.query(YourDuckdbRef, sql, [log.id, log.team_id, log.message, log.runtime])
    end)
  rescue
    e -> Logger.error("Failed to flush batch to DuckDB: #{inspect(e)}")
  end
end
