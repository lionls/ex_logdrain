defmodule ExLogdrain.Repo do
  use GenServer
  require Logger

  @db_path Path.expand("storage/logs.duckdb", File.cwd!())
  @export_interval :timer.minutes(2)
  @cleanup_interval :timer.hours(24)
  @expected_columns 30

  @create_sql """
  CREATE TABLE vercel_logs (
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
    proxy_vercel_cache VARCHAR
  );
  """

  @columns [
    :id, :deployment_id, :source, :host, :timestamp, :project_id,
    :level, :message, :project_name, :build_id, :type, :entrypoint, :request_id,
    :status_code, :path, :execution_region, :environment, :trace_id, :span_id,
    :proxy_timestamp, :proxy_method, :proxy_host, :proxy_path, :proxy_user_agent,
    :proxy_referer, :proxy_region, :proxy_status_code, :proxy_client_ip,
    :proxy_scheme, :proxy_vercel_cache
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def insert_batch(logs) do
    GenServer.cast(__MODULE__, {:insert_batch, logs})
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    File.mkdir_p!(Path.dirname(@db_path))

    {:ok, db} = Duckdbex.open(@db_path)
    {:ok, conn} = Duckdbex.connection(db)

    {:ok, _} = Duckdbex.query(conn, "SET memory_limit = '256MB';")
    {:ok, _} = Duckdbex.query(conn, "SET autoinstall_known_extensions=1;")
    {:ok, _} = Duckdbex.query(conn, "SET autoload_known_extensions=1;")

    ensure_table(conn)

    schedule_parquet_export()
    schedule_database_cleanup()

    {:ok, %{db: db, conn: conn}}
  end

  @impl true
  def handle_cast({:insert_batch, []}, state), do: {:noreply, state}

  def handle_cast({:insert_batch, logs}, %{conn: conn} = state) do
    Logger.info("Inserting #{length(logs)} log entries into DuckDB")

    try do
      {:ok, appender} = Duckdbex.appender(conn, "vercel_logs")
      Enum.each(logs, fn log ->
        values = Enum.map(@columns, &Map.get(log, &1))
        :ok = Duckdbex.appender_add_row(appender, values)
      end)

      :ok = Duckdbex.appender_flush(appender)
      :ok = Duckdbex.appender_close(appender)
    rescue
      e -> Logger.error("Insert batch failed: #{inspect(e)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:export_parquet, %{conn: conn} = state) do
    Logger.info("Exporting Parquet snapshot...")

    try do
      today = Date.utc_today() |> Date.to_string()
      dir = Path.expand("storage/archive/date=#{today}", File.cwd!())
      File.mkdir_p!(dir)
      path = Path.join(dir, "data.parquet")

      Duckdbex.query(conn, """
        COPY (
          SELECT * FROM vercel_logs
          WHERE epoch_ms(timestamp)::DATE = '#{today}'
        ) TO '#{path}' (FORMAT 'PARQUET', OVERWRITE_OR_IGNORE TRUE);
      """)

      Logger.info("Parquet snapshot written to #{path}")
    rescue
      e -> Logger.error("Parquet export failed: #{inspect(e)}")
    end

    schedule_parquet_export()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_database, %{conn: conn} = state) do
    Logger.info("Running database cleanup...")

    try do
      {:ok, _} =
        Duckdbex.query(conn, """
          DELETE FROM vercel_logs
          WHERE epoch_ms(timestamp) < CURRENT_DATE - INTERVAL 3 DAY;
        """)

      {:ok, _} = Duckdbex.query(conn, "CHECKPOINT;")
      Logger.info("Cleanup complete")
    rescue
      e -> Logger.error("Cleanup failed: #{inspect(e)}")
    end

    schedule_database_cleanup()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{conn: conn, db: db}) do
    Duckdbex.release(conn)
    Duckdbex.release(db)
    :ok
  end

  defp ensure_table(conn) do
    {:ok, _} = Duckdbex.query(conn, "CREATE TABLE IF NOT EXISTS vercel_logs (id VARCHAR);")

    {:ok, result} = Duckdbex.query(conn, "PRAGMA table_info('vercel_logs');")
    rows = Duckdbex.fetch_all(result)

    if length(rows) != @expected_columns do
      Logger.info(
        "Schema drift detected (#{length(rows)} cols, expected #{@expected_columns}), recreating..."
      )

      {:ok, _} = Duckdbex.query(conn, "DROP TABLE vercel_logs;")
      {:ok, _} = Duckdbex.query(conn, @create_sql)
    end
  end

  defp schedule_parquet_export do
    Process.send_after(self(), :export_parquet, @export_interval)
  end

  defp schedule_database_cleanup do
    Process.send_after(self(), :cleanup_database, @cleanup_interval)
  end
end
