defmodule ExLogdrain.Router do
  use Plug.Router
  import Plug.Conn

  require Logger

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: JSON,
    body_reader: {ExLogdrain.Plugs.CacheBodyReader, :read_body, []}
  )

  plug(:match)

  plug(ExLogdrain.Plugs.VerifyVercelSignature)
  plug(:dispatch)

  post "/api/v1/drain/:team_id" do
    logs = conn.body_params

    IO.inspect(logs, label: "Incoming Logs for Team #{team_id}")

    log_payload = %{
      id: Map.get(conn.body_params, "id"),
      team_id: team_id,
      message: Map.get(conn.body_params, "message"),
      runtime: Map.get(conn.body_params, "runtime")
    }

    IO.puts("Route matched! Enqueueing payload for ID: #{inspect(log_payload)}")
    ExLogdrain.LogBuffer.enqueue(log_payload)

    send_resp(conn, 200, "OK\n")
  end

  match _ do
    send_resp(conn, 404, "Not Found\n")
  end
end
