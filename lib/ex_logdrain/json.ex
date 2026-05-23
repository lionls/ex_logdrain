defmodule ExLogdrain.Json do
  def decode!(body, _opts \\ [])
  def decode!("", _opts), do: nil
  def decode!(nil, _opts), do: nil
  def decode!(body, _opts), do: :json.decode(body)

  def encode(value) do
    :json.encode(value) |> IO.iodata_to_binary()
  end
end
