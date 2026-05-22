defmodule ExLogdrain.Plugs.VerifyVercelSignature do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    secret_key = Application.get_env(:ex_logdrain, :vercel_webhook_secret)

    [received_signature] = get_req_header(conn, "x-vercel-signature")
    raw_body = conn.assigns[:raw_body] || ""

    expected_signature =
      :crypto.mac(:hmac, :sha256, secret_key, raw_body)
      |> Base.encode16(case: :lower)

    IO.inspect(received_signature, label: "RECEIVED FROM CURL")
    IO.inspect(expected_signature, label: "EXPECTED BY ELIXIR")

    if :crypto.hash_equals(received_signature, expected_signature) do
      conn
    else
      conn
      |> send_resp(401, "Unauthorized: Signature mismatch\n")
      |> halt()
    end
  rescue
    _ ->
      conn
      |> send_resp(401, "Unauthorized\n")
      |> halt()
  end
end
