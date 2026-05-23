defmodule ExLogdrain.Repo do
  use GenServer
  require Logger

  @db_path Path.expand("storage/logs.duckdb", File.cwd!())

  # Export to Parquet every 2 minutes instead of on every batch write
  @export_interval :timer.minutes(2)
  @cleanup_interval :timer.hours(24)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Asynchronously writes a batch of memory items straight through the alive connection"
  def insert_batch(logs) do
    GenServer.cast(__MODULE__, {:insert_batch, logs})
  end

  def get_connection, do: GenServer.call(__MODULE__, :get_connection)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    File.mkdir_p!(Path.dirname(@db_path))

    {:ok, db} = Duckdbex.open(@db_path)
    {:ok, conn} = Duckdbex.connection(db)

    {:ok, _} = Duckdbex.query(conn, "SET memory_limit = '256MB';")

    {:ok, _} = Duckdbex.query(conn, "SET autoinstall_known_extensions=1;")
    {:ok, _} = Duckdbex.query(conn, "SET autoload_known_extensions=1;")

    # Tables auto-commit by default. No need for Duckdbex.commit/1 here.
    {:ok, _result_ref} =
      Duckdbex.query(
        conn,
        """
        CREATE TABLE IF NOT EXISTS vercel_logs (
          id VARCHAR,
          team_id VARCHAR,
          message VARCHAR,
          runtime VARCHAR
        );
        """
        |> String.trim()
      )

    # Schedule the recurring background Parquet snapshot
    schedule_parquet_export()
    schedule_database_cleanup()

    {:ok, %{db: db, conn: conn}}
  end

  @impl true
  def handle_call(:get_connection, _from, state) do
    {:reply, {:ok, state.db, state.conn}, state}
  end

  @impl true
  def handle_cast({:insert_batch, []}, state), do: {:noreply, state}

  def handle_cast({:insert_batch, logs}, %{conn: conn} = state) do
    Logger.info("Repo Database Worker: Committing #{length(logs)} records natively to disk...")

    try do
      {:ok, appender} = Duckdbex.appender(conn, "vercel_logs")

      Enum.each(logs, fn log ->
        :ok = Duckdbex.appender_add_row(appender, [log.id, log.team_id, log.message, log.runtime])
      end)

      :ok = Duckdbex.appender_flush(appender)
      # Closing the appender immediately flushes metadata changes cleanly
      :ok = Duckdbex.appender_close(appender)
    rescue
      e -> Logger.error("Critical: Disk writer operation aborted: #{inspect(e)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:export_parquet, %{conn: conn} = state) do
    Logger.info("Repo Database Worker: Generating background Parquet snapshot...")

    try do
      today_str = Date.utc_today() |> Date.to_string()

      partition_dir = Path.expand("storage/archive/date=#{today_str}", File.cwd!())
      File.mkdir_p!(partition_dir)

      target_parquet_path = Path.join(partition_dir, "data.parquet")

      Duckdbex.query(
        conn,
        """
          COPY (
            SELECT id, team_id, message, runtime, inserted_at
            FROM vercel_logs
            WHERE CAST(inserted_at AS DATE) = '#{today_str}'
          ) TO '#{target_parquet_path}' (FORMAT 'PARQUET', OVERWRITE_OR_IGNORE TRUE);
        """
        |> String.trim()
      )

      Logger.info("Repo Database Worker: Snapshot successfully written to #{target_parquet_path}")
    rescue
      e -> Logger.error("Failed to export partitioned Parquet snapshot: #{inspect(e)}")
    end

    schedule_parquet_export()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_database, %{conn: conn} = state) do
    Logger.info("Repo Maintenance: Starting automated rolling data truncation...")

    try do
      {:ok, _} =
        Duckdbex.query(
          conn,
          """
            DELETE FROM vercel_logs
            WHERE inserted_at < CURRENT_DATE - INTERVAL 3 DAY;
          """
          |> String.trim()
        )

      {:ok, _} = Duckdbex.query(conn, "CHECKPOINT;")

      Logger.info("Repo Maintenance: Database cleanup and space optimization complete.")
    rescue
      e -> Logger.error("Repo Maintenance: Cleanup routine failed: #{inspect(e)}")
    end

    schedule_database_cleanup()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{conn: conn, db: db}) do
    Logger.info("Gracefully releasing persistent DuckDB disk assets...")
    Duckdbex.release(conn)
    Duckdbex.release(db)
    :ok
  end

  defp schedule_parquet_export do
    Process.send_after(self(), :export_parquet, @export_interval)
  end

  defp schedule_database_cleanup do
    Process.send_after(self(), :cleanup_database, @cleanup_interval)
  end
end
