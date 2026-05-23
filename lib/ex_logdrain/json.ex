defmodule ExLogdrain.Json do
  def decode!(body, _opts \\ [])
  def decode!("", _opts), do: nil
  def decode!(nil, _opts), do: nil
  def decode!(body, _opts), do: :json.decode(body)

  def try_decode(body) do
    try do
      :json.decode(body)
    rescue
      _ -> nil
    end
  end

  def encode(value) do
    :json.encode(value) |> IO.iodata_to_binary()
  end
end
