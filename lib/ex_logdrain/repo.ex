defmodule ExLogdrain.Repo do
  use GenServer
  require Logger

  @db_path "storage/logs.duckdb"
  @snapshot_interval :timer.minutes(15)
  @expected_columns 30

  @create_table """
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
    File.mkdir_p!("storage")

    {:ok, db} = Duckdbex.open(@db_path)
    {:ok, conn} = Duckdbex.connection(db)

    {:ok, _} = Duckdbex.query(conn, "SET memory_limit = '256MB';")
    {:ok, _} = Duckdbex.query(conn, "SET autoinstall_known_extensions=1;")
    {:ok, _} = Duckdbex.query(conn, "SET autoload_known_extensions=1;")

    configure_s3(conn)
    ensure_table(conn)
    schedule_snapshot()

    {:ok, %{db: db, conn: conn}}
  end

  @impl true
  def handle_cast({:insert_batch, []}, state), do: {:noreply, state}

  def handle_cast({:insert_batch, logs}, %{conn: conn} = state) do
    try do
      {:ok, appender} = Duckdbex.appender(conn, "vercel_logs")
      Enum.each(logs, fn log ->
        values = Enum.map(@columns, &Map.get(log, &1))
        :ok = Duckdbex.appender_add_row(appender, values)
      end)
      :ok = Duckdbex.appender_flush(appender)
      :ok = Duckdbex.appender_close(appender)
    rescue
      e -> Logger.error("Insert failed: #{inspect(e)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:snapshot, %{conn: conn} = state) do
    try do
      now = DateTime.utc_now()
      path = snapshot_path(now)

      Duckdbex.query(conn, """
        COPY (SELECT * FROM vercel_logs)
        TO '#{path}' (FORMAT 'PARQUET');
      """)

      {:ok, _} = Duckdbex.query(conn, "DELETE FROM vercel_logs;")
      {:ok, _} = Duckdbex.query(conn, "CHECKPOINT;")

      Logger.info("Snapshot flushed to #{path}")
    rescue
      e -> Logger.error("Snapshot failed: #{inspect(e)}")
    end

    schedule_snapshot()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{conn: conn, db: db}) do
    Duckdbex.release(conn)
    Duckdbex.release(db)
    :ok
  end

  defp configure_s3(conn) do
    bucket = Application.get_env(:ex_logdrain, :s3_bucket)
    _ = bucket && do_configure_s3(conn)
  end

  defp do_configure_s3(conn) do
    {:ok, _} = Duckdbex.query(conn, "INSTALL httpfs;")
    {:ok, _} = Duckdbex.query(conn, "LOAD httpfs;")

    region = Application.get_env(:ex_logdrain, :s3_region, "us-east-1")
    key = Application.get_env(:ex_logdrain, :s3_access_key_id, "")
    secret = Application.get_env(:ex_logdrain, :s3_secret_access_key, "")

    {:ok, _} = Duckdbex.query(conn, "SET s3_region='#{region}';")
    {:ok, _} = Duckdbex.query(conn, "SET s3_access_key_id='#{key}';")
    {:ok, _} = Duckdbex.query(conn, "SET s3_secret_access_key='#{secret}';")

    endpoint = Application.get_env(:ex_logdrain, :s3_endpoint)
    if endpoint do
      {:ok, _} = Duckdbex.query(conn, "SET s3_endpoint='#{endpoint}';")
      {:ok, _} = Duckdbex.query(conn, "SET s3_use_ssl=false;")
      {:ok, _} = Duckdbex.query(conn, "SET s3_url_style='path';")
    end
  end

  defp snapshot_path(now) do
    bucket = Application.get_env(:ex_logdrain, :s3_bucket)

    date = now |> DateTime.to_date() |> Date.to_string()
    hour = pad(now.hour)
    minute = pad(now.minute)
    id = System.unique_integer([:positive]) |> Integer.to_string(36)

    filename = "#{hour}-#{minute}_#{id}.parquet"
    rel = "logs/date=#{date}/#{filename}"

    if bucket do
      "s3://#{bucket}/#{rel}"
    else
      dir = "storage/logs/date=#{date}"
      File.mkdir_p!(dir)
      Path.join(dir, filename)
    end
  end

  defp ensure_table(conn) do
    {:ok, _} = Duckdbex.query(conn, "CREATE TABLE IF NOT EXISTS vercel_logs (id VARCHAR);")

    {:ok, result} = Duckdbex.query(conn, "PRAGMA table_info('vercel_logs');")
    rows = Duckdbex.fetch_all(result)

    if length(rows) != @expected_columns do
      Logger.info("Schema drift (#{length(rows)} cols, expected #{@expected_columns}), recreating...")
      {:ok, _} = Duckdbex.query(conn, "DROP TABLE vercel_logs;")
      {:ok, _} = Duckdbex.query(conn, @create_table)
    end
  end

  defp schedule_snapshot do
    Process.send_after(self(), :snapshot, @snapshot_interval)
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
