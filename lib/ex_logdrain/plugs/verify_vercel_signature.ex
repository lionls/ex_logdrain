defmodule ExLogdrain.Plugs.VerifyVercelSignature do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.method == "POST" && String.starts_with?(conn.request_path, "/vercel") do
      auth(conn)
    else
      conn
    end
  end

  defp auth(conn) do
    case get_req_header(conn, "x-vercel-verify") do
      [token] when is_binary(token) and token != "" ->
        conn
        |> send_resp(200, token)
        |> halt()

      _ ->
        verify_signature(conn)
    end
  end

  defp verify_signature(conn) do
    secret = Application.get_env(:ex_logdrain, :vercel_webhook_secret)

    [signature] = get_req_header(conn, "x-vercel-signature")
    raw_body = conn.assigns[:raw_body] || ""

    expected =
      :crypto.mac(:hmac, :sha, secret, raw_body)
      |> :binary.encode_hex(:lowercase)

    if :crypto.hash_equals(signature, expected) do
      conn
    else
      Logger.warning("Signature mismatch from #{inspect(conn.remote_ip)}")
      conn |> send_resp(401, "Unauthorized\n") |> halt()
    end
  rescue
    e ->
      Logger.error("Signature verification error: #{inspect(e)}")
      conn |> send_resp(401, "Unauthorized\n") |> halt()
  end
end
