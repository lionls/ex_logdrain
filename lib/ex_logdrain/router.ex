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

  post "/api/v1/drain" do
    Enum.each(conn.body_params, fn log ->
      payload = %{
        id: log["id"],
        deployment_id: log["deploymentId"],
        source: log["source"],
        host: log["host"],
        timestamp: log["timestamp"],
        project_id: log["projectId"],
        level: log["level"],
        message: log["message"],
        project_name: log["projectName"],
        build_id: log["buildId"],
        type: log["type"],
        entrypoint: log["entrypoint"],
        request_id: log["requestId"],
        status_code: log["statusCode"],
        path: log["path"],
        execution_region: log["executionRegion"],
        environment: log["environment"],
        trace_id: log["traceId"] || get_in(log, ["trace", "id"]),
        span_id: log["spanId"] || get_in(log, ["span", "id"]),
        proxy_timestamp: get_in(log, ["proxy", "timestamp"]),
        proxy_method: get_in(log, ["proxy", "method"]),
        proxy_host: get_in(log, ["proxy", "host"]),
        proxy_path: get_in(log, ["proxy", "path"]),
        proxy_user_agent: encode_user_agent(get_in(log, ["proxy", "userAgent"])),
        proxy_referer: get_in(log, ["proxy", "referer"]),
        proxy_region: get_in(log, ["proxy", "region"]),
        proxy_status_code: get_in(log, ["proxy", "statusCode"]),
        proxy_client_ip: get_in(log, ["proxy", "clientIp"]),
        proxy_scheme: get_in(log, ["proxy", "scheme"]),
        proxy_vercel_cache: get_in(log, ["proxy", "vercelCache"])
      }

      ExLogdrain.LogBuffer.enqueue(payload)
    end)

    send_resp(conn, 200, "OK\n")
  end

  match _ do
    send_resp(conn, 404, "Not Found\n")
  end

  defp encode_user_agent(nil), do: nil
  defp encode_user_agent(ua) when is_list(ua), do: Enum.join(ua, ",")
  defp encode_user_agent(ua), do: ua
end
