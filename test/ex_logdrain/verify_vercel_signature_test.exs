defmodule ExLogdrain.VerifyVercelSignatureTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  @secret "test_secret"
  @endpoint "/vercel"

  defp sign(body) do
    :crypto.mac(:hmac, :sha, @secret, body)
    |> :binary.encode_hex(:lowercase)
  end

  test "passes through non-POST requests" do
    conn = ExLogdrain.Plugs.VerifyVercelSignature.call(conn(:get, @endpoint), [])
    refute conn.halted
    assert conn.status == nil
  end

  test "passes through requests to other paths" do
    conn = ExLogdrain.Plugs.VerifyVercelSignature.call(conn(:post, "/health"), [])
    refute conn.halted
    assert conn.status == nil
  end

  test "vercel-verify handshake echoes the token" do
    conn =
      conn(:post, @endpoint)
      |> put_req_header("x-vercel-verify", "abc123")
      |> ExLogdrain.Plugs.VerifyVercelSignature.call([])

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "abc123"
  end

  test "valid signature passes through" do
    body = ~s([{"id":"42","message":"test"}])
    sig = sign(body)

    conn =
      conn(:post, @endpoint)
      |> put_req_header("x-vercel-signature", sig)
      |> assign(:raw_body, body)
      |> ExLogdrain.Plugs.VerifyVercelSignature.call([])

    refute conn.halted
    assert conn.status == nil
  end

  test "invalid signature returns 401" do
    body = ~s([{"id":"42","message":"test"}])

    conn =
      conn(:post, @endpoint)
      |> put_req_header("x-vercel-signature", "bad000bad000")
      |> assign(:raw_body, body)
      |> ExLogdrain.Plugs.VerifyVercelSignature.call([])

    assert conn.halted
    assert conn.status == 401
  end

  test "missing signature header returns 401" do
    conn =
      conn(:post, @endpoint)
      |> ExLogdrain.Plugs.VerifyVercelSignature.call([])

    assert conn.halted
    assert conn.status == 401
  end

  test "empty raw_body falls back to empty string" do
    sig = sign("")

    conn =
      conn(:post, @endpoint)
      |> put_req_header("x-vercel-signature", sig)
      |> ExLogdrain.Plugs.VerifyVercelSignature.call([])

    refute conn.halted
  end
end
