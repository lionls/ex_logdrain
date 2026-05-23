defmodule ExLogdrain.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  import Plug.Test

  @opts ExLogdrain.Router.init([])

  test "GET /health returns 200 OK" do
    conn = conn(:get, "/health") |> ExLogdrain.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body == "OK\n"
  end

  test "POST /vercel with valid log entries returns 200" do
    body = ExLogdrain.Json.encode([
      %{id: "abc", message: "test log", level: "info", timestamp: 1_700_000_000_000}
    ])

    sig = sign(body)

    conn =
      conn(:post, "/vercel", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-vercel-signature", sig)
      |> assign(:raw_body, body)
      |> ExLogdrain.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body == "OK\n"
  end

  test "POST /vercel verification handshake echoes token" do
    conn =
      conn(:post, "/vercel", "")
      |> put_req_header("x-vercel-verify", "tokentest")
      |> ExLogdrain.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body == "tokentest"
  end

  test "unknown route returns 404" do
    conn = conn(:get, "/nope") |> ExLogdrain.Router.call(@opts)

    assert conn.status == 404
    assert conn.resp_body == "Not Found\n"
  end

  test "POST /vercel with invalid signature returns 401" do
    body = ExLogdrain.Json.encode([%{id: "42"}])

    conn =
      conn(:post, "/vercel", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-vercel-signature", "badtoken")
      |> assign(:raw_body, body)
      |> ExLogdrain.Router.call(@opts)

    assert conn.status == 401
  end

  test "POST /vercel with empty body returns 200" do
    sig = sign("")

    conn =
      conn(:post, "/vercel", "")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-vercel-signature", sig)
      |> assign(:raw_body, "")
      |> ExLogdrain.Router.call(@opts)

    assert conn.status == 200
  end

  defp sign(body) do
    :crypto.mac(:hmac, :sha, "test_secret", body)
    |> :binary.encode_hex(:lowercase)
  end
end
