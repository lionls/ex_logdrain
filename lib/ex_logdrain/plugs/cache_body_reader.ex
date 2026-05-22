defmodule ExLogdrain.Plugs.CacheBodyReader do
  @moduledoc """
  Intercepts the raw network socket read to copy the binary body
  into the connection before any JSON decoding takes place.
  """
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.assign(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
