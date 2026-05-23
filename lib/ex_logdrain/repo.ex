defmodule ExLogdrain.Repo do
  use GenServer
  require Logger

  @db_path Path.expand("storage/logs.duckdb", File.cwd!())

  @export_interval :timer.minutes(2)
  @cleanup_interval :timer.hours(24)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

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

    {:ok, _result_ref} =
      Duckdbex.query(
        conn,
        """
        CREATE TABLE IF NOT EXISTS vercel_logs (
          id VARCHAR,
          deployment_id VARCHAR,
          source VARCHAR,
          host VARCHAR,
          timestamp BIGINT,
          project_id VARCHAR,
          level VARCHAR,
          message VARCHAR,
          project_name VARCHAR,
          build_id VARCHAR,
          type VARCHAR,
          entrypoint VARCHAR,
          request_id VARCHAR,
          status_code INTEGER,
          path VARCHAR,
          execution_region VARCHAR,
          environment VARCHAR,
          trace_id VARCHAR,
          span_id VARCHAR,
          proxy_timestamp BIGINT,
          proxy_method VARCHAR,
          proxy_host VARCHAR,
          proxy_path VARCHAR,
          proxy_user_agent VARCHAR,
          proxy_referer VARCHAR,
          proxy_region VARCHAR,
          proxy_status_code INTEGER,
          proxy_client_ip VARCHAR,
          proxy_scheme VARCHAR,
          proxy_vercel_cache VARCHAR,
          inserted_at TIMESTAMPTZ
        );
        """
        |> String.trim()
      )

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

      now = DateTime.utc_now()

      Enum.each(logs, fn log ->
        :ok =
          Duckdbex.appender_add_row(appender, [
            log.id,
            log.deployment_id,
            log.source,
            log.host,
            log.timestamp,
            log.project_id,
            log.level,
            log.message,
            log.project_name,
            log.build_id,
            log.type,
            log.entrypoint,
            log.request_id,
            log.status_code,
            log.path,
            log.execution_region,
            log.environment,
            log.trace_id,
            log.span_id,
            log.proxy_timestamp,
            log.proxy_method,
            log.proxy_host,
            log.proxy_path,
            log.proxy_user_agent,
            log.proxy_referer,
            log.proxy_region,
            log.proxy_status_code,
            log.proxy_client_ip,
            log.proxy_scheme,
            log.proxy_vercel_cache,
            now
          ])
      end)

      :ok = Duckdbex.appender_flush(appender)
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
            SELECT * FROM vercel_logs
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
